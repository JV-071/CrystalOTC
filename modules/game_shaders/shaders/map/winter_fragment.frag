uniform float u_Time;
uniform sampler2D u_Tex0; // game screen
uniform sampler2D u_Tex1; // snow
varying vec2 v_TexCoord;
uniform vec2 u_WalkOffset;
uniform float u_CurrentOpacity;

void main(void)
{
  vec3 Game = texture2D(u_Tex0, v_TexCoord).xyz;
  
  vec2 snowDir1 = vec2(-0.5, 1.0);
  float snowSpeed1 = 0.06;
  float snowZoom1 = 0.15;
  vec2 SnowHandler1 = (v_TexCoord + vec2(u_WalkOffset.x, u_WalkOffset.y) + (snowDir1 * u_Time * snowSpeed1)) / snowZoom1;
  vec3 Snow1 = texture2D(u_Tex1, SnowHandler1).xyz;
  
  vec2 snowDir2 = vec2(0.3, 1.2);
  float snowSpeed2 = 0.08;
  float snowZoom2 = 0.20;
  vec2 SnowHandler2 = (v_TexCoord + vec2(u_WalkOffset.x, u_WalkOffset.y) + (snowDir2 * u_Time * snowSpeed2)) / snowZoom2;
  vec3 Snow2 = texture2D(u_Tex1, SnowHandler2).xyz;
  
  vec2 snowDir3 = vec2(-0.2, 1.5);
  float snowSpeed3 = 0.10;
  float snowZoom3 = 0.25;
  vec2 SnowHandler3 = (v_TexCoord + vec2(u_WalkOffset.x, u_WalkOffset.y) + (snowDir3 * u_Time * snowSpeed3)) / snowZoom3;
  vec3 Snow3 = texture2D(u_Tex1, SnowHandler3).xyz;

  vec3 SnowCombined = (Snow1 * 0.5) + (Snow2 * 0.3) + (Snow3 * 0.2);
  
  vec3 _output = Game + SnowCombined * u_CurrentOpacity;
  gl_FragColor = vec4(_output, 1.0);
}
