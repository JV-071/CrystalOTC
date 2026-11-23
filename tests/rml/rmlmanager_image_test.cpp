#include <gtest/gtest.h>

#include <framework/graphics/image.h>
#include <framework/rml/rmlmanager.h>

#include <stdexcept>
#include <string>
#include <vector>

namespace {

    // RmlManager::loadImage resolves the sources RmlUi asks for. Game sprites are "virtual"
    // images (item/<id>.png, effect/<id>.png, outfit/<n>-<n>-...png) built by a provider.
    struct Provider
    {
        int calls{ 0 };
        std::string kind;
        std::vector<int> args;
        ImagePtr image;
        bool fail{ false };

        void attach(RmlManager& manager)
        {
            manager.setImageProvider([this](const std::string_view requestedKind, const std::vector<int>& requestedArgs) -> ImagePtr {
                ++calls;
                kind = requestedKind;
                args = requestedArgs;
                if (fail)
                    throw std::runtime_error("sprite file busy");
                return image;
            });
        }
    };

    // 2x2 RGBA image whose four pixels are all different
    ImagePtr fourPixels()
    {
        const uint8_t pixels[16]{ 10, 0, 0, 255, 20, 0, 0, 255, 30, 0, 0, 255, 40, 0, 0, 255 };
        return std::make_shared<Image>(Size(2, 2), 4, pixels);
    }

    bool isTransparentPlaceholder(const ImagePtr& image)
    {
        if (!image || image->getSize() != Size(32, 32))
            return false;
        for (const auto byte : image->getPixels())
            if (byte != 0)
                return false;
        return true;
    }

    TEST(RmlImages, AVirtualImageComesFromTheProvider)
    {
        RmlManager manager;
        Provider provider;
        provider.image = fourPixels();
        provider.attach(manager);

        const auto image = manager.loadImage("item/3031.png");

        ASSERT_NE(image, nullptr);
        EXPECT_EQ(image->getSize(), Size(2, 2));
        EXPECT_EQ(provider.kind, "item");
        EXPECT_EQ(provider.args, std::vector<int>{ 3031 });
    }

    TEST(RmlImages, OutfitArgumentsArriveInOrder)
    {
        RmlManager manager;
        Provider provider;
        provider.image = fourPixels();
        provider.attach(manager);

        manager.loadImage("/modules/x/outfit/128-78-69-58-76-3-2.png");

        EXPECT_EQ(provider.kind, "outfit");
        const std::vector<int> expected{ 128, 78, 69, 58, 76, 3, 2 };
        EXPECT_EQ(provider.args, expected);
    }

    TEST(RmlImages, TheScaleSuffixEnlargesWithoutBlurring)
    {
        RmlManager manager;
        Provider provider;
        provider.image = fourPixels();
        provider.attach(manager);

        const auto image = manager.loadImage("item/3031@3x.png");

        ASSERT_NE(image, nullptr);
        ASSERT_EQ(image->getSize(), Size(6, 6));
        EXPECT_EQ(provider.args, std::vector<int>{ 3031 });
        const auto& pixels = image->getPixels();
        const auto red = [&](const int x, const int y) { return pixels[(static_cast<size_t>(y) * 6 + x) * 4]; };
        EXPECT_EQ(red(0, 0), 10); EXPECT_EQ(red(2, 2), 10); // the whole 3x3 block of source pixel (0,0)
        EXPECT_EQ(red(3, 0), 20); EXPECT_EQ(red(5, 2), 20);
        EXPECT_EQ(red(0, 3), 30); EXPECT_EQ(red(5, 5), 40);
    }

    TEST(RmlImages, AnImageTheProviderCannotBuildIsATransparentPlaceholder)
    {
        RmlManager manager;
        Provider provider; // returns nullptr: invalid id, or assets without that thing
        provider.attach(manager);

        EXPECT_TRUE(isTransparentPlaceholder(manager.loadImage("item/99999999.png")));
        EXPECT_EQ(provider.calls, 1);
    }

    TEST(RmlImages, TheProviderIsNotAskedBeforeTheAssetsAreReady)
    {
        RmlManager manager;
        Provider provider;
        provider.image = fourPixels();
        provider.attach(manager);
        bool ready = false;
        manager.setAssetsReadyCheck([&ready] { return ready; });

        EXPECT_TRUE(isTransparentPlaceholder(manager.loadImage("effect/5.png")));
        EXPECT_EQ(provider.calls, 0);

        ready = true;
        const auto image = manager.loadImage("effect/5.png");
        ASSERT_NE(image, nullptr);
        EXPECT_EQ(image->getSize(), Size(2, 2));
        EXPECT_EQ(provider.calls, 1);
    }

    TEST(RmlImages, AProviderFailureDoesNotEscape)
    {
        RmlManager manager;
        Provider provider;
        provider.fail = true;
        provider.attach(manager);

        ImagePtr image;
        EXPECT_NO_THROW(image = manager.loadImage("outfit/128-0-0-0-0-0-2.png"));
        EXPECT_TRUE(isTransparentPlaceholder(image));
    }

}
