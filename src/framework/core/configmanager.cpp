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

#include "configmanager.h"
#include <INIReader.h>
#include "resourcemanager.h"

#include <cctype>
#include <fstream>

ConfigManager g_configs;

void ConfigManager::init() {
    m_settings = std::make_shared<Config>();

    // Comment out or remove this line to skip loading config.ini.
    loadPublicConfig("config.ini");
}

void ConfigManager::terminate()
{
    if (m_settings) {
        // ensure settings are saved
        m_settings->save();

        m_settings->unload();
        m_settings = nullptr;
    }

    for (auto config : m_configs) {
        config->unload();
        config = nullptr;
    }

    m_configs.clear();
}

ConfigPtr ConfigManager::getSettings()
{
    return m_settings;
}

ConfigPtr ConfigManager::get(const std::string& file)
{
    for (const auto& config : m_configs) {
        if (config->getFileName() == file) {
            return config;
        }
    }
    return nullptr;
}

ConfigPtr ConfigManager::loadSettings(const std::string& file)
{
    if (file.empty()) {
        g_logger.error("Must provide a configuration file to load.");
    } else {
        if (m_settings->load(file)) {
            return m_settings;
        }
    }
    return nullptr;
}

ConfigPtr ConfigManager::create(const std::string& file)
{
    auto config = load(file);
    if (!config) {
        config = std::make_shared<Config>();

        config->load(file);
        config->save();

        m_configs.emplace_back(config);
    }
    return config;
}

ConfigPtr ConfigManager::load(const std::string& file)
{
    if (file.empty()) {
        g_logger.error("Must provide a configuration file to load.");
        return nullptr;
    }
    auto config = get(file);
    if (!config) {
        config = std::make_shared<Config>();

        if (config->load(file)) {
            m_configs.emplace_back(config);
        } else {
            // cannot load config
            config = nullptr;
        }
    }
    return config;
}

std::string ConfigManager::normalizeRenderBackend(const std::string& backend)
{
    std::string value = backend;
    stdext::trim(value);
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

    if (value == "d3d11" || value == "opengl" || value == "vulkan")
        return value;
    return "auto";
}

void ConfigManager::setRenderBackend(const std::string& requested)
{
    const std::string backend = normalizeRenderBackend(requested);
    if (backend == "auto" && requested != "auto" && requested != "gl")
        g_logger.warning("[config] unknown render backend '{}' - using auto", requested);

    m_publicConfig.graphics.renderBackend = backend;

    // config.ini sits next to the exe and is a plain text file; we rewrite only the
    // renderBackend key of the [graphics] section (the only place loadPublicConfig reads it
    // from), so comments and the rest of the user's settings stay. The file is not shipped
    // with the client (it is gitignored), so it is created when missing.
    const std::string path = "config.ini";
    const std::string entry = "renderBackend = " + backend;

    std::vector<std::string> lines;
    if (std::ifstream in(path); in.is_open()) {
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty() && line.back() == '\r')
                line.pop_back();
            lines.push_back(line);
        }
    }

    const auto lowerTrimmed = [](std::string text) {
        stdext::trim(text);
        std::transform(text.begin(), text.end(), text.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return text;
    };
    const auto isRenderBackendKey = [&](const std::string& line) {
        const std::string text = lowerTrimmed(line);
        if (text.rfind("renderbackend", 0) != 0)
            return false;
        std::string rest = text.substr(13);
        stdext::trim(rest);
        return !rest.empty() && (rest[0] == '=' || rest[0] == ':');
    };

    std::vector<std::string> output;
    std::string section;
    bool written = false;
    bool hasGraphics = false;

    for (const auto& line : lines) {
        const std::string text = lowerTrimmed(line);
        if (!text.empty() && text.front() == '[') {
            // leaving [graphics] without a renderBackend key: add it at the end of the section
            if (section == "[graphics]" && !written) {
                output.push_back(entry);
                written = true;
            }
            section = text;
            if (section == "[graphics]")
                hasGraphics = true;
            output.push_back(line);
            continue;
        }

        if (isRenderBackendKey(line)) {
            // a key outside [graphics] is never read (older clients appended it at the end of
            // the file, whatever section that was), so it is dropped instead of kept stale
            if (section == "[graphics]" && !written) {
                output.push_back(entry);
                written = true;
            }
            continue;
        }

        output.push_back(line);
    }

    if (!written) {
        if (!hasGraphics) {
            if (!output.empty() && !output.back().empty())
                output.emplace_back();
            output.emplace_back("[graphics]");
        }
        output.push_back(entry);
    }

    std::ofstream out(path, std::ios::trunc);
    if (!out.is_open()) {
        g_logger.warning("[config] cannot write {}", path);
        return;
    }

    for (const auto& l : output)
        out << l << "\n";

    g_logger.info("[config] render backend set to '{}' - takes effect after a client restart", backend);
}

bool ConfigManager::unload(const std::string& file)
{
    if (auto config = get(file)) {
        config->unload();
        remove(config);
        config = nullptr;
        return true;
    }
    return false;
}

void ConfigManager::remove(const ConfigPtr& config) { m_configs.remove(config); }

void ConfigManager::saveSettings()
{
    if (m_settings)
        m_settings->save();
}

void ConfigManager::loadPublicConfig(const std::string& fileName) {
    try {
        auto content = g_resources.readFileContents(fileName);
        INIReader reader(content.c_str(), content.size());

        if (reader.ParseError() < 0) {
            g_logger.error("Failed to read config otml '{}''", fileName);
            return;
        }

        m_publicConfig.graphics.maxAtlasSize = std::max<int>(2048, reader.GetInteger("graphics", "maxAtlasSize", m_publicConfig.graphics.maxAtlasSize));
        m_publicConfig.graphics.mapAtlasSize = reader.GetInteger("graphics", "mapAtlasSize", m_publicConfig.graphics.mapAtlasSize);
        m_publicConfig.graphics.foregroundAtlasSize = reader.GetInteger("graphics", "foregroundAtlasSize", m_publicConfig.graphics.foregroundAtlasSize);
        m_publicConfig.graphics.renderBackend = normalizeRenderBackend(reader.Get("graphics", "renderBackend", m_publicConfig.graphics.renderBackend));
        
        m_publicConfig.font.widget = reader.Get("font", "widget", m_publicConfig.font.widget);
        m_publicConfig.font.staticText = reader.Get("font", "static-text", m_publicConfig.font.staticText);
        m_publicConfig.font.animatedText = reader.Get("font", "animated-text", m_publicConfig.font.animatedText);
        m_publicConfig.font.creatureText = reader.Get("font", "creature-text", m_publicConfig.font.creatureText);
        m_publicConfig.font.itemCount = reader.Get("font", "item-count", m_publicConfig.font.itemCount);

        m_publicConfig.debug.memoryLog = reader.GetBoolean("debug", "memoryLog", m_publicConfig.debug.memoryLog);
    } catch (const std::exception& e) {
        g_logger.error("Failed to parse public config '{}': {}", fileName, e.what());
    }
}