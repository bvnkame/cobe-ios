#include <metal_stdlib>
using namespace metal;

// ============================================================
// Uniform structs (must match Swift CobeRenderer layouts)
// ============================================================

struct GlobeUniforms {
    float2 uResolution;
    float2 uOffset;
    float2 uRotation;        // (phi, theta)
    float  uDots;
    float  uScale;
    float3 uBaseColor;
    float  _pad0;
    float3 uGlowColor;
    float  _pad1;
    float4 uRenderParams;    // (dotsBrightness, diffuse, dark, opacity)
    float  uMapBaseBrightness;
};

struct MarkerArcUniforms {
    float  uPhi;
    float  uTheta;
    float2 uResolution;
    float  uScale;
    float2 uOffset;
    float  uMarkerElevation;
    float  uPerspective;
    float3 _pad;
    float3 uColor;           // markerColor for marker, arcColor for arc
};

// ============================================================
// GLOBE
// ============================================================

struct GlobeVOut {
    float4 position [[position]];
};

vertex GlobeVOut globe_vertex(uint vid [[vertex_id]],
                              const device float2* aPosition [[buffer(0)]]) {
    GlobeVOut o;
    o.position = float4(aPosition[vid], 0.0, 1.0);
    return o;
}

static float3x3 rotate3(float theta, float phi) {
    float cx = cos(theta), cy = cos(phi);
    float sx = sin(theta), sy = sin(phi);
    return float3x3(
        float3(cy, sy * sx, -sy * cx),
        float3(0.0, cx, sx),
        float3(sy, cy * -sx, cy * cx)
    );
}

constant float sqrt5 = 2.236068;
constant float PI    = 3.141593;
constant float kTau  = 6.283185;
constant float kPhi  = 1.618034;
constant float R     = 0.8;

static float3 nearestFibonacciLattice(float3 pIn, float dots, thread float &m) {
    float3 p = pIn.xzy;
    float byDots = 1.0 / dots;

    float k = max(2.0, floor(log2(sqrt5 * dots * PI * (1.0 - p.z * p.z)) * 0.72021));
    float2 f = floor(pow(kPhi, k) / sqrt5 * float2(1.0, kPhi) + 0.5);
    float2 br1 = fract((f + 1.0) * (kPhi - 1.0)) * kTau - 3.883222;
    float2 br2 = -2.0 * f;
    float2 sp = float2(atan2(p.y, p.x), p.z - 1.0);
    float2 c = floor(float2(br2.y * sp.x - br1.y * (sp.y * dots + 1.0),
                            -br2.x * sp.x + br1.x * (sp.y * dots + 1.0))
                     / (br1.x * br2.y - br2.x * br1.y));

    float mindist = PI;
    float3 minip = float3(0.0);

    for (float s = 0.0; s < 4.0; s += 1.0) {
        float2 o = float2(fmod(s, 2.0), floor(s * 0.5));
        float idx = dot(f, c + o);
        if (idx > dots) continue;

        float a = idx, b = 0.0;
        if (a >= 16384.0) { a -= 16384.0; b += 0.868872; }
        if (a >= 8192.0)  { a -= 8192.0;  b += 0.934436; }
        if (a >= 4096.0)  { a -= 4096.0;  b += 0.467218; }
        if (a >= 2048.0)  { a -= 2048.0;  b += 0.733609; }
        if (a >= 1024.0)  { a -= 1024.0;  b += 0.866804; }
        if (a >= 512.0)   { a -= 512.0;   b += 0.433402; }
        if (a >= 256.0)   { a -= 256.0;   b += 0.216701; }
        if (a >= 128.0)   { a -= 128.0;   b += 0.108351; }
        if (a >= 64.0)    { a -= 64.0;    b += 0.554175; }
        if (a >= 32.0)    { a -= 32.0;    b += 0.777088; }
        if (a >= 16.0)    { a -= 16.0;    b += 0.888544; }
        if (a >= 8.0)     { a -= 8.0;     b += 0.944272; }
        if (a >= 4.0)     { a -= 4.0;     b += 0.472136; }
        if (a >= 2.0)     { a -= 2.0;     b += 0.236068; }
        if (a >= 1.0)     { a -= 1.0;     b += 0.618034; }

        float theta = fract(b) * kTau;
        float cosphi = 1.0 - 2.0 * idx * byDots;
        float sinphi = sqrt(1.0 - cosphi * cosphi);
        float3 samp = float3(cos(theta) * sinphi, sin(theta) * sinphi, cosphi);
        float dist = length(p - samp);
        if (dist < mindist) {
            mindist = dist;
            minip = samp;
        }
    }
    m = mindist;
    return minip.xzy;
}

fragment float4 globe_fragment(GlobeVOut in [[stage_in]],
                               constant GlobeUniforms& U [[buffer(0)]],
                               texture2d<float> tex [[texture(0)]],
                               sampler texSampler [[sampler(0)]]) {
    float2 invResolution = 1.0 / U.uResolution;
    // Metal: position.y origin top-left; GL: bottom-left. Flip y to match cobe.
    float2 frag = float2(in.position.x, U.uResolution.y - in.position.y);
    float2 uv = ((frag * invResolution) * 2.0 - 1.0) / U.uScale - U.uOffset * float2(1.0, -1.0) * invResolution;
    uv.x *= U.uResolution.x * invResolution.y;

    float l = dot(uv, uv);
    float glowFactor = 0.0;
    float4 color = float4(0.0);

    if (l <= R * R) {
        float dis;
        float3 p = normalize(float3(uv, sqrt(R * R - l)));
        float3x3 rot = rotate3(U.uRotation.y, U.uRotation.x);
        float dotNL = p.z;

        float3 gP = nearestFibonacciLattice(p * rot, U.uDots, dis);

        float gPhi = asin(gP.y);
        float gTheta = acos(-gP.x / cos(gPhi));
        if (gP.z < 0.0) gTheta = -gTheta;

        float2 tuv = float2((gTheta * 0.5) / PI, -(gPhi / PI + 0.5));
        float mapColor = max(tex.sample(texSampler, tuv).x, U.uMapBaseBrightness);

        float samp = mapColor
            * smoothstep(0.008, 0.0, dis)
            * pow(dotNL, U.uRenderParams.y)
            * U.uRenderParams.x;

        float3 layer = U.uBaseColor
            * (mix((1.0 - samp) * pow(dotNL, 0.4), samp, U.uRenderParams.z) + 0.1)
            + pow(1.0 - dotNL, 4.0) * U.uGlowColor;

        color = float4(layer, 1.0) * (1.0 + U.uRenderParams.w) * 0.5;
        glowFactor = (1.0 - l) * (1.0 - l) * smoothstep(0.0, 1.0, 0.2 / (l - R * R));
    } else {
        float outD = sqrt(0.2 / (l - R * R));
        glowFactor = smoothstep(0.5, 1.0, outD / (outD + 1.0));
    }
    return color + float4(glowFactor * U.uGlowColor, glowFactor);
}

// ============================================================
// MARKER (instanced)
// ============================================================

struct MarkerInstance {
    float3 pos;
    float  size;
    float3 color;
    float  hasColor;
};

struct MarkerVOut {
    float4 position [[position]];
    float2 uv;
    float3 color;
    float  hasColor;
    float  fade;
};

vertex MarkerVOut marker_vertex(uint vid [[vertex_id]],
                                uint iid [[instance_id]],
                                const device float2* quad [[buffer(0)]],
                                const device MarkerInstance* inst [[buffer(1)]],
                                constant MarkerArcUniforms& U [[buffer(2)]]) {
    MarkerInstance m = inst[iid];
    float2 aPos = quad[vid];

    float cx = cos(U.uTheta), sx = sin(U.uTheta);
    float cy = cos(U.uPhi),   sy = sin(U.uPhi);
    float3 p = m.pos * (0.8 + U.uMarkerElevation);
    float3 rp = float3(
        cy * p.x + sy * p.z,
        sy * sx * p.x + cx * p.y - cy * sx * p.z,
        -sy * cx * p.x + sx * p.y + cy * cx * p.z
    );

    MarkerVOut o;
    float occluded = (rp.z < 0.0 && length(rp.xy) < 0.8) ? 1.0 : 0.0;
    float fade = occluded * 0.0 + (1.0 - occluded) * smoothstep(-0.15, 0.15, rp.z);

    // Perspective: closer (rp.z higher) → larger marker. Lerp by uPerspective.
    float depthScale = mix(1.0, 0.5 + max(0.0, rp.z) * 0.9, U.uPerspective);
    float ia = U.uResolution.y / U.uResolution.x;
    float2 pos = (rp.xy + aPos * m.size * depthScale * 2.0) * float2(ia, 1.0) * U.uScale + U.uOffset * float2(1.0, -1.0) * U.uScale / U.uResolution;
    o.position = float4(pos, 0.0, 1.0);
    o.uv = aPos;
    o.color = m.color;
    o.hasColor = m.hasColor;
    o.fade = fade;
    return o;
}

fragment float4 marker_fragment(MarkerVOut in [[stage_in]],
                                constant MarkerArcUniforms& U [[buffer(0)]]) {
    if (length(in.uv) > 0.25) discard_fragment();
    if (in.fade <= 0.001) discard_fragment();
    float3 col = in.hasColor > 0.5 ? in.color : U.uColor;
    return float4(col, in.fade);
}

// ============================================================
// ARC (instanced ribbon along bezier)
// ============================================================

struct ArcInstance {
    float3 from;
    float3 to;
    float  height;
    float  width;
    float3 color;
    float  hasColor;
};

struct ArcVOut {
    float4 position [[position]];
    float3 color;
    float  hasColor;
    float  depth;
    float  radialDist;
};

static float3 bezierPoint(float3 p0, float3 p1, float3 p2, float t) {
    float u = 1.0 - t;
    return u * u * p0 + 2.0 * u * t * p1 + t * t * p2;
}

static float3 bezierTangent(float3 p0, float3 p1, float3 p2, float t) {
    float u = 1.0 - t;
    return 2.0 * u * (p1 - p0) + 2.0 * t * (p2 - p1);
}

vertex ArcVOut arc_vertex(uint vid [[vertex_id]],
                          uint iid [[instance_id]],
                          const device float2* seg [[buffer(0)]],
                          const device ArcInstance* inst [[buffer(1)]],
                          constant MarkerArcUniforms& U [[buffer(2)]]) {
    ArcInstance a = inst[iid];
    float2 aPos = seg[vid];
    float3x3 rot = rotate3(U.uTheta, U.uPhi);

    float endpointR = R + U.uMarkerElevation;
    float3 from = a.from * endpointR;
    float3 to   = a.to   * endpointR;

    float3 midSum = a.from + a.to;
    float midLen = length(midSum);
    float3 midDir = midLen > 0.001 ? midSum / midLen : float3(0.0, 1.0, 0.0);
    float3 mid = midDir * (R + a.height);

    float t = aPos.x;
    float3 arcPoint = bezierPoint(from, mid, to, t);
    float3 rotatedPoint = rot * arcPoint;

    float3 rawTangent = bezierTangent(from, mid, to, t);
    float3 rotatedTangent = rot * rawTangent;

    float2 screenTangent = rotatedTangent.xy;
    float screenTangentLen = length(screenTangent);
    float2 screenPerp = screenTangentLen > 0.001
        ? float2(-screenTangent.y, screenTangent.x) / screenTangentLen
        : float2(1.0, 0.0);

    float aspect = U.uResolution.x / U.uResolution.y;
    float2 baseScreenPos = rotatedPoint.xy * float2(1.0 / aspect, 1.0) * U.uScale + U.uOffset * float2(1.0, -1.0) * U.uScale / U.uResolution;
    float2 screenPos = baseScreenPos + screenPerp * a.width * aPos.y * U.uScale;

    ArcVOut o;
    o.position = float4(screenPos, 0.0, 1.0);
    o.color = a.color;
    o.hasColor = a.hasColor;
    o.depth = rotatedPoint.z;
    o.radialDist = length(rotatedPoint.xy);
    return o;
}

fragment float4 arc_fragment(ArcVOut in [[stage_in]],
                             constant MarkerArcUniforms& U [[buffer(0)]]) {
    if (in.depth < 0.0 && in.radialDist < R) discard_fragment();
    float fade = smoothstep(-0.15, 0.15, in.depth);
    float3 col = in.hasColor > 0.5 ? in.color : U.uColor;
    return float4(col, fade);
}
