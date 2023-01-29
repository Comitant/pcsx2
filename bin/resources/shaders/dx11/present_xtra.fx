
#ifdef SHADER_MODEL

#define JSSS_NUM 3
#define JSSS_HALF (JSSS_NUM/2)
#define JSSS_RCP2 (1.0/(JSSS_NUM*JSSS_NUM))

#if 1
#define GAMMA_PRE(x) ((x)*(x))
#define GAMMA_POST(x) (sqrt(x))
#else
#define GAMMA_PRE(x) (x)
#define GAMMA_POST(x) (x)
#endif

float nrand(float2 n) {
	
  return frac(sin(dot(n, float2(12.9898, 78.233)))* 43758.5453) - 0.5;
}

PS_OUTPUT ps_jittered_stochastic_supersampling(PS_INPUT input)
{
	PS_OUTPUT output;
	
	float3 color = 0;
	float2 dxy = float2(ddx(input.t.x), ddy(input.t.y)) / JSSS_NUM;

	for(int j = -JSSS_HALF; j <= JSSS_HALF; j++)
	for(int i = -JSSS_HALF; i <= JSSS_HALF; i++) {
		float rx = nrand(input.t * u_time + i + j);
		float ry = nrand(input.t * u_time + i + j + 0.5);
		
		float2 offset = float2(i,j) + float2(rx,ry);
		float3 sample = sample_c(input.t + offset * dxy).rgb;
		color += GAMMA_PRE(sample);
	}

	output.c = float4(GAMMA_POST(color*JSSS_RCP2), 1);
	return output;
}

PS_OUTPUT ps_nxn_uniform_grid_supersampling(PS_INPUT input)
{
	PS_OUTPUT output;
	
	float3 color = 0;
	float2 dxy = float2(ddx(input.t.x), ddy(input.t.y)) / JSSS_NUM;
	
	for(int j = -JSSS_HALF; j <= JSSS_HALF; j++)
	for(int i = -JSSS_HALF; i <= JSSS_HALF; i++) {
		float3 sample = sample_c(input.t +  float2(i,j) * dxy).rgb;
		color += GAMMA_PRE(sample);
	}

	output.c = float4(GAMMA_POST(color*JSSS_RCP2), 1);
	return output;
}

PS_OUTPUT ps_quincunx(PS_INPUT input)
{
	PS_OUTPUT output;
	
	float2 dxy = float2(ddx(input.t.x), ddy(input.t.y));
	float3 sample, color = 0;
	
	sample = sample_c(input.t + float2( 0.25, 0.25) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t + float2( 0.25,-0.25) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t + float2(-0.25,-0.25) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t + float2(-0.25, 0.25) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t).rgb;
	
	color = color * 0.125 + GAMMA_PRE(sample) * 0.5;

	output.c = float4(GAMMA_POST(color), 1);
	return output;
}

PS_OUTPUT ps_4x_rgss(PS_INPUT input)
{
	PS_OUTPUT output;
	
	float2 dxy = float2(ddx(input.t.x), ddy(input.t.y));
	float3 sample, color = 0;
	
	float s = 1.0/8.0;
	float l = 3.0/8.0;
	
	sample = sample_c(input.t + float2( s, l) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t + float2( l,-s) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t + float2(-s,-l) * dxy).rgb; color += GAMMA_PRE(sample);
	sample = sample_c(input.t + float2(-l, s) * dxy).rgb; color += GAMMA_PRE(sample);
		   
	output.c = float4(GAMMA_POST(color * 0.25),1);
	return output;
}

// https://www.shadertoy.com/view/MllBWf
// Pixel Art Filtering

// default 0.75, smoother
#define MAGIC 0.5

PS_OUTPUT ps_nearest_aa(PS_INPUT input)
{
	PS_OUTPUT output;
	
	float2 uv = input.t * u_source_resolution + 0.5;
	float2 fl = floor(uv);
	float2 fr = frac(uv);
	float2 aa = fwidth(uv) * MAGIC;
	fr = smoothstep(0.5 - aa, 0.5 + aa, fr);
	
	output.c = sample_c((fl+fr-0.5)*u_rcp_source_resolution);
	return output;
}
#endif
