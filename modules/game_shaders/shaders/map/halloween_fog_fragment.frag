uniform float u_Time;
uniform sampler2D u_Tex0;      // Textura do mapa
uniform sampler2D u_Tex1;      // Textura da névoa (fog.png)
uniform vec2 u_WalkOffset;     // Offset do movimento do personagem
uniform float u_CurrentOpacity;

varying vec2 v_TexCoord;

void main() {
    // Cor base do mapa
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    
    // Movimento da névoa da DIREITA para ESQUERDA
    vec2 direction = vec2(-1.0, 0.0);  // Movimento horizontal para esquerda
    float speed = 0.04;
    
    // Coordenada base com compensação do walkOffset
    vec2 baseCoord = v_TexCoord + vec2(u_WalkOffset.x, u_WalkOffset.y) + (direction * u_Time * speed);

    // Usar múltiplas camadas com escalas e offsets diferentes
    vec2 fogUV1 = baseCoord;
    vec2 fogUV2 = baseCoord * 1.3 + vec2(0.33, 0.1);
    vec2 fogUV3 = baseCoord * 0.7 + vec2(0.66, -0.1);
    
    // Aplicar wrapping suave
    fogUV1.x = fract(fogUV1.x);
    fogUV2.x = fract(fogUV2.x);
    fogUV3.x = fract(fogUV3.x);
    
    // Ler as três camadas
    vec4 fog1 = texture2D(u_Tex1, fogUV1);
    vec4 fog2 = texture2D(u_Tex1, fogUV2);
    vec4 fog3 = texture2D(u_Tex1, fogUV3);
    
    // Misturar usando multiplicação ao invés de soma
    vec4 fogTexture = fog1;
    fogTexture.rgb = mix(fogTexture.rgb, fog2.rgb, fog2.a * 0.5);
    fogTexture.rgb = mix(fogTexture.rgb, fog3.rgb, fog3.a * 0.3);
    fogTexture.a = (fog1.a + fog2.a * 0.5 + fog3.a * 0.3) / 1.8;
    
    // Aplicar a névoa sobre o mapa
    vec3 finalColor = mix(baseColor.rgb, fogTexture.rgb, fogTexture.a * u_CurrentOpacity);
    
    gl_FragColor = vec4(finalColor, baseColor.a);
}
