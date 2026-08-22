uniform vec4 u_Color;
uniform vec4 u_OutlineColor; // Cor do outline (parametrizavel)
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;

void main()
{
    const float ALPHA_TOLERANCE = 0.1;

    // Pega a cor do pixel atual
    vec4 centerColor = texture2D(u_Tex0, v_TexCoord);
    vec4 texcolor = texture2D(u_Tex0, v_TexCoord2);
    vec4 texcolor3 = texture2D(u_Tex0, v_TexCoord3);

    vec4 finalColor = centerColor * u_Color;

    // Cria outline com cor parametrizavel
    // Se o pixel atual é transparente mas há pixel opaco ao redor, desenha a borda externa
    if (centerColor.a < ALPHA_TOLERANCE && texcolor3.a > ALPHA_TOLERANCE) {
        finalColor = vec4(0.0, 1.0, 0.0, 1.0); // Usa a cor do outline definida
    }
    // Se o pixel atual é opaco e está na borda (próximo a área transparente), desenha borda interna
    else if (centerColor.a > ALPHA_TOLERANCE && texcolor3.a < ALPHA_TOLERANCE) {
        // Mistura a cor original com a cor do outline para criar borda interna
        finalColor.rgb = finalColor.rgb * 0.5 + vec4(0.0, 1.0, 0.0, 1.0).rgb * 0.5;
    }

    gl_FragColor = finalColor;

    if(gl_FragColor.a < 0.01) {
        discard;
    }
}