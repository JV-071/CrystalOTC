#include <gtest/gtest.h>

#include <framework/platform/platformwindow.h>
#include <framework/rml/rmlbackend.h>

namespace {

    // The test process never creates a window, so there is no OpenGL context: the same situation
    // as the client running its pure-Vulkan mode. RmlUi must then report "no executor" instead of
    // trying to draw (and must never create a GL context of its own).
    TEST(RmlBackendFactory, WithoutGlContextThereIsNoExecutor)
    {
#ifndef _WIN32
        // Only the Windows window reports a missing GL context; the other platforms always answer
        // true (PlatformWindow::hasGLContext default), so the premise of this test does not hold.
        GTEST_SKIP() << "hasGLContext() is only overridden by the Windows window";
#endif
        ASSERT_FALSE(g_window.hasGLContext());

        EXPECT_EQ(rmlExpectedBackendName(), "none");
        EXPECT_EQ(createRmlBackend(), nullptr);
        EXPECT_FALSE(g_window.hasGLContext());
    }

}
