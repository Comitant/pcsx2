// SPDX-FileCopyrightText: 2002-2025 PCSX2 Dev Team
// SPDX-License-Identifier: GPL-3.0+

#ifdef VERTEX_SHADER

layout(location = 0) in vec4 a_pos;
layout(location = 1) in vec2 a_tex;

layout(location = 0) out vec2 v_tex;

void main()
{
	gl_Position = vec4(a_pos.x, -a_pos.y, a_pos.z, a_pos.w);
	v_tex = a_tex;
}

#endif

#ifdef FRAGMENT_SHADER

layout(push_constant) uniform cb10
{
	vec4 u_source_rect;
	vec4 u_target_rect;
	vec2 u_source_size;
	vec2 u_target_size;
	vec2 u_target_resolution;
	vec2 u_rcp_target_resolution; // 1 / u_target_resolution
	vec2 u_source_resolution;
	vec2 u_rcp_source_resolution; // 1 / u_source_resolution
	float u_time;
};

layout(location = 0) in vec2 v_tex;

layout(location = 0) out vec4 o_col0;

layout(set = 0, binding = 0) uniform sampler2D samp0;

vec4 sample_c(vec2 uv)
{
	return texture(samp0, uv);
}

vec4 ps_crt(uint i)
{
	vec4 mask[4] = vec4[4](
		vec4(1, 0, 0, 0),
		vec4(0, 1, 0, 0),
		vec4(0, 0, 1, 0),
		vec4(1, 1, 1, 0));
	return sample_c(v_tex) * clamp((mask[i] + 0.5f), 0.0f, 1.0f);
}

vec4 ps_scanlines(uint i)
{
	vec4 mask[2] =
		{
			vec4(1, 1, 1, 0),
			vec4(0, 0, 0, 0)};

	return sample_c(v_tex) * clamp((mask[i] + 0.5f), 0.0f, 1.0f);
}

#ifdef ps_copy
void ps_copy()
{
	o_col0 = sample_c(v_tex);
}
#endif

#ifdef ps_filter_scanlines
void ps_filter_scanlines() // scanlines
{
	uvec4 p = uvec4(gl_FragCoord);

	o_col0 = ps_scanlines(p.y % 2);
}
#endif

#ifdef ps_filter_diagonal
void ps_filter_diagonal() // diagonal
{
	uvec4 p = uvec4(gl_FragCoord);
	o_col0 = ps_crt((p.x + (p.y % 3)) % 3);
}
#endif

#ifdef ps_filter_triangular
void ps_filter_triangular() // triangular
{
	uvec4 p = uvec4(gl_FragCoord);

	// output.c = ps_crt(input, ((p.x + (p.y & 1) * 3) >> 1) % 3);
	o_col0 = ps_crt(((p.x + ((p.y >> 1) & 1) * 3) >> 1) % 3);
}
#endif

#ifdef ps_filter_complex
void ps_filter_complex() // triangular
{
	const float PI = 3.14159265359f;
	vec2 texdim = vec2(textureSize(samp0, 0));

	o_col0 = (0.9 - 0.4 * cos(2 * PI * v_tex.y * texdim.y)) * sample_c(vec2(v_tex.x, (floor(v_tex.y * texdim.y) + 0.5) / texdim.y));
}
#endif

#ifdef ps_filter_lottes

#define MaskingType 4                      //[1|2|3|4] The type of CRT shadow masking used. 1: compressed TV style, 2: Aperture-grille, 3: Stretched VGA style, 4: VGA style.
#define ScanBrightness -8.00               //[-16.0 to 1.0] The overall brightness of the scanline effect. Lower for darker, higher for brighter.
#define FilterCRTAmount -3.00              //[-4.0 to 1.0] The amount of filtering used, to replicate the TV CRT look. Lower for less, higher for more.
#define HorizontalWarp 0.00                //[0.0 to 0.1] The distortion warping effect for the horizontal (x) axis of the screen. Use small increments.
#define VerticalWarp 0.00                  //[0.0 to 0.1] The distortion warping effect for the verticle (y) axis of the screen. Use small increments.
#define MaskAmountDark 0.50                //[0.0 to 1.0] The value of the dark masking line effect used. Lower for darker lower end masking, higher for brighter.
#define MaskAmountLight 1.50               //[0.0 to 2.0] The value of the light masking line effect used. Lower for darker higher end masking, higher for brighter.
#define BloomPixel -1.50                   //[-2.0 -0.5] Pixel bloom radius. Higher for increased softness of bloom.
#define BloomScanLine -2.0                 //[-4.0 -1.0] Scanline bloom radius. Higher for increased softness of bloom.
#define BloomAmount 0.15                   //[0.0 1.0] Bloom intensity. Higher for brighter.
#define Shape 2.0                          //[0.0 10.0] Kernal filter shape. Lower values will darken image and introduce moire patterns if used with curvature.
#define UseShadowMask 1                    //[0 or 1] Enables, or disables the use of the CRT shadow mask. 0 is disabled, 1 is enabled.

float ToLinear1(float c)
{
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec3 ToLinear(vec3 c)
{
	return vec3(ToLinear1(c.r), ToLinear1(c.g), ToLinear1(c.b));
}

float ToSrgb1(float c)
{
	return c < 0.0031308 ? c * 12.92 : 1.055 * pow(c, 0.41666) - 0.055;
}

vec3 ToSrgb(vec3 c)
{
	return vec3(ToSrgb1(c.r), ToSrgb1(c.g), ToSrgb1(c.b));
}

vec3 Fetch(vec2 pos, vec2 off)
{
	pos = (floor(pos * u_target_size + off) + vec2(0.5, 0.5)) / u_target_size;
	if (max(abs(pos.x - 0.5), abs(pos.y - 0.5)) > 0.5)
	{
		return vec3(0.0, 0.0, 0.0);
	}
	else
	{
		return ToLinear(texture(samp0, pos.xy).rgb);
	}
}

vec2 Dist(vec2 pos)
{
	pos = pos * vec2(640, 480);

	return -((pos - floor(pos)) - vec2(0.5, 0.5));
}

float Gaus(float pos, float scale)
{
	return exp2(scale * pow(abs(pos), Shape));
}

vec3 Horz3(vec2 pos, float off)
{
	vec3 b = Fetch(pos, vec2(-1.0, off));
	vec3 c = Fetch(pos, vec2(0.0, off));
	vec3 d = Fetch(pos, vec2(1.0, off));
	float dst = Dist(pos).x;

	// Convert distance to weight.
	float scale = FilterCRTAmount;
	float wb = Gaus(dst - 1.0, scale);
	float wc = Gaus(dst + 0.0, scale);
	float wd = Gaus(dst + 1.0, scale);

	return (b * wb + c * wc + d * wd) / (wb + wc + wd);
}

vec3 Horz5(vec2 pos, float off)
{
	vec3 a = Fetch(pos, vec2(-2.0, off));
	vec3 b = Fetch(pos, vec2(-1.0, off));
	vec3 c = Fetch(pos, vec2(0.0, off));
	vec3 d = Fetch(pos, vec2(1.0, off));
	vec3 e = Fetch(pos, vec2(2.0, off));
	float dst = Dist(pos).x;

	// Convert distance to weight.
	float scale = FilterCRTAmount;

	float wa = Gaus(dst - 2.0, scale);
	float wb = Gaus(dst - 1.0, scale);
	float wc = Gaus(dst + 0.0, scale);
	float wd = Gaus(dst + 1.0, scale);
	float we = Gaus(dst + 2.0, scale);

	return (a * wa + b * wb + c * wc + d * wd + e * we) / (wa + wb + wc + wd + we);
}

vec3 Horz7(vec2 pos, float off)
{
	vec3 a = Fetch(pos, vec2(-3.0, off));
	vec3 b = Fetch(pos, vec2(-2.0, off));
	vec3 c = Fetch(pos, vec2(-1.0, off));
	vec3 d = Fetch(pos, vec2( 0.0, off));
	vec3 e = Fetch(pos, vec2( 1.0, off));
	vec3 f = Fetch(pos, vec2( 2.0, off));
	vec3 g = Fetch(pos, vec2( 3.0, off));

	float dst = Dist(pos).x;
	// Convert distance to weight.
	float scale = BloomPixel;
	float wa = Gaus(dst - 3.0, scale);
	float wb = Gaus(dst - 2.0, scale);
	float wc = Gaus(dst - 1.0, scale);
	float wd = Gaus(dst + 0.0, scale);
	float we = Gaus(dst + 1.0, scale);
	float wf = Gaus(dst + 2.0, scale);
	float wg = Gaus(dst + 3.0, scale);

	// Return filtered sample.
	return (a * wa + b * wb + c * wc + d * wd + e * we + f * wf + g * wg) / (wa + wb + wc + wd + we + wf + wg);
}

// Return scanline weight.
float Scan(vec2 pos, float off)
{
	float dst = Dist(pos).y;
	return Gaus(dst + off, ScanBrightness);
}

float BloomScan(vec2 pos, float off)
{
	float dst = Dist(pos).y;

	return Gaus(dst + off, BloomScanLine);
}

vec3 Tri(vec2 pos)
{
	vec3 a = Horz3(pos, -1.0);
	vec3 b = Horz5(pos, 0.0);
	vec3 c = Horz3(pos, 1.0);

	float wa = Scan(pos, -1.0);
	float wb = Scan(pos, 0.0);
	float wc = Scan(pos, 1.0);

	return (a * wa) + (b * wb) + (c * wc);
}

vec3 Bloom(vec2 pos)
{
	vec3 a = Horz5(pos,-2.0);
	vec3 b = Horz7(pos,-1.0);
	vec3 c = Horz7(pos, 0.0);
	vec3 d = Horz7(pos, 1.0);
	vec3 e = Horz5(pos, 2.0);

	float wa = BloomScan(pos,-2.0);
	float wb = BloomScan(pos,-1.0); 
	float wc = BloomScan(pos, 0.0);
	float wd = BloomScan(pos, 1.0);
	float we = BloomScan(pos, 2.0);

	return a * wa + b * wb + c * wc + d * wd + e * we;
}

vec2 Warp(vec2 pos)
{
	pos = pos * 2.0 - 1.0;
	pos *= vec2(1.0 + (pos.y * pos.y) * HorizontalWarp, 1.0 + (pos.x * pos.x) * VerticalWarp);
	return pos * 0.5 + 0.5;
}

vec3 Mask(vec2 pos)
{
#if MaskingType == 1
	// Very compressed TV style shadow mask.
	float lines = MaskAmountLight;
	float odd = 0.0;

	if (fract(pos.x / 6.0) < 0.5)
	{
		odd = 1.0;
	}
	if (fract((pos.y + odd) / 2.0) < 0.5)
	{
		lines = MaskAmountDark;
	}
	pos.x = fract(pos.x / 3.0);
	vec3 mask = vec3(MaskAmountDark, MaskAmountDark, MaskAmountDark);

	if (pos.x < 0.333)
	{
		mask.r = MaskAmountLight;
	}
	else if (pos.x < 0.666)
	{
		mask.g = MaskAmountLight;
	}
	else
	{
		mask.b = MaskAmountLight;
	}

	mask *= lines;

	return mask;

#elif MaskingType == 2
	// Aperture-grille.
	pos.x = fract(pos.x / 3.0);
	vec3 mask = vec3(MaskAmountDark, MaskAmountDark, MaskAmountDark);

	if (pos.x < 0.333)
	{
		mask.r = MaskAmountLight;
	}
	else if (pos.x < 0.666)
	{
		mask.g = MaskAmountLight;
	}
	else
	{
		mask.b = MaskAmountLight;
	}

	return mask;

#elif MaskingType == 3
	// Stretched VGA style shadow mask (same as prior shaders).
	pos.x += pos.y * 3.0;
	vec3 mask = vec3(MaskAmountDark, MaskAmountDark, MaskAmountDark);
	pos.x = fract(pos.x / 6.0);

	if (pos.x < 0.333)
	{
		mask.r = MaskAmountLight;
	}
	else if (pos.x < 0.666)
	{
		mask.g = MaskAmountLight;
	}
	else
	{
		mask.b = MaskAmountLight;
	}

	return mask;

#else
	// VGA style shadow mask.
	pos.xy = floor(pos.xy * vec2(1.0, 0.5));
	pos.x += pos.y * 3.0;

	vec3 mask = vec3(MaskAmountDark, MaskAmountDark, MaskAmountDark);
	pos.x = fract(pos.x / 6.0);

	if (pos.x < 0.333)
	{
		mask.r = MaskAmountLight;
	}
	else if (pos.x < 0.666)
	{
		mask.g = MaskAmountLight;
	}
	else
	{
		mask.b = MaskAmountLight;
	}
	return mask;
#endif
}

vec4 LottesCRTPass()
{
	vec4 color;
	vec4 fragcoord = gl_FragCoord - u_target_rect;
	vec2 inSize = u_target_resolution - (2 * u_target_rect.xy);

	vec2 pos = Warp(fragcoord.xy / inSize);
	color.rgb = Tri(pos);
	color.rgb += Bloom(pos) * BloomAmount;
#if UseShadowMask
	color.rgb *= Mask(fragcoord.xy);
#endif
	color.rgb = ToSrgb(color.rgb);

	return color;
}

void ps_filter_lottes()
{
	o_col0 = LottesCRTPass();
}

#endif

#ifdef ps_4x_rgss
void ps_4x_rgss()
{
	vec2 dxy = vec2(dFdx(v_tex.x), dFdy(v_tex.y));
	vec3 color = vec3(0);

	float s = 1.0/8.0;
	float l = 3.0/8.0;

	color += sample_c(v_tex + vec2( s, l) * dxy).rgb;
	color += sample_c(v_tex + vec2( l,-s) * dxy).rgb;
	color += sample_c(v_tex + vec2(-s,-l) * dxy).rgb;
	color += sample_c(v_tex + vec2(-l, s) * dxy).rgb;

	o_col0 = vec4(color * 0.25,1);
}
#endif

#ifdef ps_automagical_supersampling
#define GSample0 sum += sample_c(base_uv).rgb;
#define GSample(x, y) sum += sample_c(base_uv + step_uv * vec2(x, y)).rgb;
void ps_automagical_supersampling() {
    vec2 dx = dFdx(v_tex);
    vec2 dy = dFdy(v_tex);
    
    vec2 scale = (abs(dx) + abs(dy)) * u_source_resolution;
    float max_scale = max(scale.x, scale.y);
    
    if (max_scale < 1.0) {
        o_col0 = sample_c(v_tex);
        return;
    }
    
    vec2 pixel_center = v_tex * u_source_resolution;
    vec2 half_scale = scale * 0.5;
    vec2 box_start = pixel_center - half_scale;
    vec2 box_end = pixel_center + half_scale;
    
    if (max_scale >= 3.0) {
        int grid_size = max_scale >= 6.0 ? 5 : (max_scale >= 4.0 ? 4 : 3);
        float rcp_samples = max_scale >= 6.0 ? 0.04 : (max_scale >= 4.0 ? 0.0625 : 0.111111);
        
        vec2 step = (box_end - box_start) / float(grid_size);
        vec2 base_uv = (box_start + step * 0.5) * u_rcp_source_resolution;
        vec2 step_uv = step * u_rcp_source_resolution;
        
        vec3 sum = vec3(0.0);
        
        if (grid_size == 3) {
            GSample0 GSample(1.0, 0.0) GSample(2.0, 0.0)
            GSample(0.0, 1.0) GSample(1.0, 1.0) GSample(2.0, 1.0)
            GSample(0.0, 2.0) GSample(1.0, 2.0) GSample(2.0, 2.0)
        } else if (grid_size == 4) {
            GSample0 GSample(1.0, 0.0) GSample(2.0, 0.0) GSample(3.0, 0.0)
            GSample(0.0, 1.0) GSample(1.0, 1.0) GSample(2.0, 1.0) GSample(3.0, 1.0)
            GSample(0.0, 2.0) GSample(1.0, 2.0) GSample(2.0, 2.0) GSample(3.0, 2.0)
            GSample(0.0, 3.0) GSample(1.0, 3.0) GSample(2.0, 3.0) GSample(3.0, 3.0)
        } else {
            GSample0 GSample(1.0, 0.0) GSample(2.0, 0.0) GSample(3.0, 0.0) GSample(4.0, 0.0)
            GSample(0.0, 1.0) GSample(1.0, 1.0) GSample(2.0, 1.0) GSample(3.0, 1.0) GSample(4.0, 1.0)
            GSample(0.0, 2.0) GSample(1.0, 2.0) GSample(2.0, 2.0) GSample(3.0, 2.0) GSample(4.0, 2.0)
            GSample(0.0, 3.0) GSample(1.0, 3.0) GSample(2.0, 3.0) GSample(3.0, 3.0) GSample(4.0, 3.0)
            GSample(0.0, 4.0) GSample(1.0, 4.0) GSample(2.0, 4.0) GSample(3.0, 4.0) GSample(4.0, 4.0)
        }
        
        o_col0 = vec4(sum * rcp_samples, 1.0);
        return;
    }
    
    // Analytical path for sub-3x scale
    box_start = clamp(box_start, vec2(0.0), u_source_resolution);
    box_end = clamp(box_end, vec2(0.0), u_source_resolution);
    
    ivec2 pix_start = ivec2(floor(box_start));
    ivec2 pix_end = ivec2(ceil(box_end));
    
    float EPS = 1.0 / max(u_source_resolution.x, u_source_resolution.y);
    vec3 sum = vec3(0.0);
    float total_weight = 0.0;
    
    for (int y = pix_start.y; y < pix_end.y; ++y) {
        float sample_start_y = max(box_start.y, float(y));
        float sample_end_y = min(box_end.y, float(y + 1));
        float height = sample_end_y - sample_start_y;
        if (height <= EPS) continue;
        
        for (int x = pix_start.x; x < pix_end.x; ++x) {
            float sample_start_x = max(box_start.x, float(x));
            float sample_end_x = min(box_end.x, float(x + 1));
            float width = sample_end_x - sample_start_x;
            if (width <= EPS) continue;
            
            float area = width * height;
            vec2 texel_center = vec2(float(x), float(y)) + 0.5;
            vec2 uv = texel_center * u_rcp_source_resolution;
            
            vec3 color = textureGrad(samp0, uv, vec2(0.0), vec2(0.0)).rgb;
            sum += color * area;
            total_weight += area;
        }
    }
    
    o_col0 = vec4(sum / max(total_weight, EPS), 1.0);
}
#endif

#endif
