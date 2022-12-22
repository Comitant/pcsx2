#ifdef FRAGMENT_SHADER

vec4 sample_c(vec2 pos)
{
	return texture(TextureSampler, pos);
}

#if 1
#define GAMMA_PRE(x) ((x)*(x))
#define GAMMA_POST(x) (sqrt(x))
#else
#define GAMMA_PRE(x) (x)
#define GAMMA_POST(x) (x)
#endif

#define JSSS_NUM 3
#define JSSS_HALF (JSSS_NUM/2)
#define JSSS_RCP2 (1.0/(JSSS_NUM*JSSS_NUM))

float nrand(vec2 n) {
	
  return fract(sin(dot(n, vec2(12.9898, 78.233)))* 43758.5453) - 0.5;
}

#ifdef ps_jittered_stochastic_supersampling
void ps_jittered_stochastic_supersampling()
{
	vec3 color = vec3(0);
	vec2 dxy = vec2(dFdx(PSin_t.x), dFdy(PSin_t.y)) / JSSS_NUM;
	
	float rx = nrand(PSin_t * u_time);
	float ry = nrand(PSin_t * u_time + 0.5);
	
	for(int j = -JSSS_HALF; j <= JSSS_HALF; j++)
	for(int i = -JSSS_HALF; i <= JSSS_HALF; i++) {
		float rx = nrand(PSin_t * u_time + i + j);
		float ry = nrand(PSin_t * u_time + i + j + 0.5);
		
		vec2 offset = vec2(i,j) + vec2(rx,ry);
		vec3 tmpcol = sample_c(PSin_t + offset * dxy).rgb;
		color += GAMMA_PRE(tmpcol);
	}

	SV_Target0 = vec4(GAMMA_POST(color*JSSS_RCP2), 1);
}
#endif

#ifdef ps_nxn_uniform_grid_supersampling
void ps_nxn_uniform_grid_supersampling()
{
	vec3 color = vec3(0);
	vec2 dxy = vec2(dFdx(PSin_t.x), dFdy(PSin_t.y)) / JSSS_NUM;
	
	for(int j = -JSSS_HALF; j <= JSSS_HALF; j++)
	for(int i = -JSSS_HALF; i <= JSSS_HALF; i++) {
		vec3 tmpcol = sample_c(PSin_t +  vec2(i,j) * dxy).rgb;
		color += GAMMA_PRE(tmpcol);
	}

	SV_Target0 = vec4(GAMMA_POST(color*JSSS_RCP2), 1);
}
#endif

#ifdef ps_quincunx
void ps_quincunx()
{
	vec2 dxy = vec2(dFdx(PSin_t.x), dFdy(PSin_t.y));
	vec3 tmpcol, color = vec3(0);
	
	tmpcol = sample_c(PSin_t + vec2( 0.25, 0.25) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t + vec2( 0.25,-0.25) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t + vec2(-0.25,-0.25) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t + vec2(-0.25, 0.25) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t).rgb;
	
	color = color * 0.125 + GAMMA_PRE(tmpcol) * 0.5;

	SV_Target0 = vec4(GAMMA_POST(color), 1);
}
#endif

#ifdef ps_4x_rgss
void ps_4x_rgss()
{
	vec2 dxy = vec2(dFdx(PSin_t.x), dFdy(PSin_t.y));
	vec3 tmpcol, color = vec3(0);
	
	float s = 1.0/8.0;
	float l = 3.0/8.0;
	
	tmpcol = sample_c(PSin_t + vec2( s, l) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t + vec2( l,-s) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t + vec2(-s,-l) * dxy).rgb; color += GAMMA_PRE(tmpcol);
	tmpcol = sample_c(PSin_t + vec2(-l, s) * dxy).rgb; color += GAMMA_PRE(tmpcol);
		   
	SV_Target0 = vec4(GAMMA_POST(color * 0.25),1);
}
#endif

#ifdef ps_nearest_aa
// https://www.shadertoy.com/view/MllBWf
// Pixel Art Filtering

// default 0.75, smoother
#define MAGIC 0.5

void ps_nearest_aa()
{
	vec2 uv = PSin_t * u_source_resolution + 0.5;
	vec2 fl = floor(uv);
	vec2 fr = fract(uv);
	vec2 aa = fwidth(uv) * MAGIC;
	fr = smoothstep(0.5 - aa, 0.5 + aa, fr);
	
	SV_Target0 = sample_c((fl+fr-0.5)*u_rcp_source_resolution);
}
#endif

#endif // FRAGMENT_SHADER
