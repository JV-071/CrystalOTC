/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#pragma once

#include "shaderprogram.h"

class PainterShaderProgram final : public ShaderProgram
{
protected:
    enum
    {
        VERTEX_ATTR = 0,
        TEXCOORD_ATTR = 1,
        PROJECTION_MATRIX_UNIFORM = 0,
        TEXTURE_MATRIX_UNIFORM = 1,
        COLOR_UNIFORM = 2,
        OPACITY_UNIFORM = 3,
        TIME_UNIFORM = 4,
        TEX0_UNIFORM = 5,
        TEX1_UNIFORM = 6,
        TEX2_UNIFORM = 7,
        TEX3_UNIFORM = 8,
        RESOLUTION_UNIFORM = 9,
        TRANSFORM_MATRIX_UNIFORM = 10
    };

    friend class Painter;

    virtual void setupUniforms();

public:
    PainterShaderProgram();

    uint8_t getId() const {
        return m_id;
    }

    bool link() override;

    void setTransformMatrix(const Matrix3& transformMatrix);
    void setProjectionMatrix(const Matrix3& projectionMatrix);
    void setTextureMatrix(const Matrix3* textureMatrix);
    void setColor(const Color& color);
    void setOpacity(float opacity);
    void setResolution(const Size& resolution);
    void updateTime();

    // Deterministic-capture support. u_Time is wall-clock derived and had no override, so any
    // shader that animates made its frame irreproducible: renderer baseline captures could not
    // gate a shader scene, and a GL-versus-Metal comparison of the same shader could never line
    // up. Pinning the value makes every animated shader render a fixed, chosen phase. Applies to
    // every program at once because the comparison is only meaningful frame-wide.
    static void setFixedTime(float seconds);
    static void clearFixedTime();
    static bool hasFixedTime();

    // The value u_Time would take right now, honouring the pin. The frame assembler needs it:
    // MaterialParams::time is frame-global, and a frame captured at an unpinned phase cannot be
    // compared with anything.
    static float currentTime();

    void addMultiTexture(const std::string& file);
    void bindMultiTextures() const;

    void setUseFramebuffer(const bool v) {
        m_useFramebuffer = v;
    }

    bool useFramebuffer() const {
        return m_useFramebuffer;
    }

private:
    // Zero means "not registered with ShaderManager", which is the case for the four
    // programs Painter builds itself - they never go through putShader. It was previously
    // left uninitialised, and PoolCompiler::materialOf turned it into a module material id,
    // so a marked creature or item (which binds the built-in replace-colour program) compiled
    // to whatever garbage the byte held.
    uint8_t m_id{ 0 };

    bool m_useFramebuffer{ false };

    float m_startTime{ 0 };
    float m_opacity{ 1.f };
    float m_time{ 0 };

    Color m_color{ Color::white };

    Matrix3 m_transformMatrix;
    Matrix3 m_projectionMatrix;
    const Matrix3* m_textureMatrix = nullptr;

    Size m_resolution;

    std::vector<TexturePtr> m_multiTextures;

    friend class ShaderManager;
};
