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

#ifdef CRYSTALOTC_COCOA_WINDOW

// Include order in this file is load-bearing three times over.
//
// 1. glutil.h comes first because it includes <GL/glew.h>, and glew hard-errors if any GL
//    header was parsed before it. It is included EXPLICITLY here: this file used to get it
//    for free through platformwindow.h -> declarations.h, and when declarations.h stopped
//    dragging GL into every consumer that free ride ended and this file stopped compiling.
//
// 2. AppKit's umbrella drags in NSOpenGL.h and therefore Apple's own gl.h/gltypes.h,
//    which define GLhandleARB as void* where glew defines it as unsigned int. This
//    translation unit wants no OpenGL at all, so Apple's gl.h and gltypes.h are switched
//    off through their own include guards and glew keeps ownership of the GL types.
//
//    Note those two guards are not sufficient on their own, which is exactly how the
//    implicit dependency above stayed invisible: OpenGL.h, CGLDevice.h and CGLIOSurface.h
//    are NOT suppressed by them and they use GLint/GLenum/GLsizei/GLuint. Something must
//    define those types, and glew is what does.
//
// 3. MacTypes.h, reached from any Apple umbrella header, defines Size, Point and Rect as
//    global legacy Memory-Manager/QuickDraw types, and the framework defines all three as
//    its own global aliases (framework/util/{size,point,rect}.h). There is no include
//    order that resolves that and no opt-out macro in the SDK, so Apple's spellings are
//    renamed for the duration of the Apple includes. Nothing here uses the legacy types;
//    NSPoint/NSRect/NSSize and CGPoint/CGRect/CGSize are distinct and untouched.
#include <framework/graphics/glutil.h>

#include "cocoawindow.h"

#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/image.h>
#include <framework/stdext/string.h>

#define __gl_h_
#define __gltypes_h_
#define GL_SILENCE_DEPRECATION

#define Size  CrystalOTCMacTypesSize
#define Point CrystalOTCMacTypesPoint
#define Rect  CrystalOTCMacTypesRect
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#undef Size
#undef Point
#undef Rect

// macOS virtual key codes. Declared here rather than pulled in from
// <Carbon/HIToolbox/Events.h> so this file does not drag in a deprecated framework for
// fifty integer constants. These are layout-independent hardware positions, which is
// exactly what the base class wants: X11Window deliberately strips Shift before its
// keysym lookup so that the physical key, not the produced character, drives Fw::Key.
enum : unsigned short
{
    VK_A = 0x00, VK_S = 0x01, VK_D = 0x02, VK_F = 0x03, VK_H = 0x04, VK_G = 0x05,
    VK_Z = 0x06, VK_X = 0x07, VK_C = 0x08, VK_V = 0x09, VK_B = 0x0B, VK_Q = 0x0C,
    VK_W = 0x0D, VK_E = 0x0E, VK_R = 0x0F, VK_Y = 0x10, VK_T = 0x11,
    VK_1 = 0x12, VK_2 = 0x13, VK_3 = 0x14, VK_4 = 0x15, VK_6 = 0x16, VK_5 = 0x17,
    VK_EQUAL = 0x18, VK_9 = 0x19, VK_7 = 0x1A, VK_MINUS = 0x1B, VK_8 = 0x1C, VK_0 = 0x1D,
    VK_RIGHTBRACKET = 0x1E, VK_O = 0x1F, VK_U = 0x20, VK_LEFTBRACKET = 0x21,
    VK_I = 0x22, VK_P = 0x23, VK_RETURN = 0x24, VK_L = 0x25, VK_J = 0x26,
    VK_APOSTROPHE = 0x27, VK_K = 0x28, VK_SEMICOLON = 0x29, VK_BACKSLASH = 0x2A,
    VK_COMMA = 0x2B, VK_SLASH = 0x2C, VK_N = 0x2D, VK_M = 0x2E, VK_PERIOD = 0x2F,
    VK_TAB = 0x30, VK_SPACE = 0x31, VK_GRAVE = 0x32, VK_BACKSPACE = 0x33,
    VK_ESCAPE = 0x35, VK_COMMAND = 0x37, VK_SHIFT = 0x38, VK_CAPSLOCK = 0x39,
    VK_OPTION = 0x3A, VK_CONTROL = 0x3B, VK_RIGHTSHIFT = 0x3C, VK_RIGHTOPTION = 0x3D,
    VK_RIGHTCONTROL = 0x3E,
    VK_KEYPAD_DECIMAL = 0x41, VK_KEYPAD_MULTIPLY = 0x43, VK_KEYPAD_PLUS = 0x45,
    VK_KEYPAD_CLEAR = 0x47, VK_KEYPAD_DIVIDE = 0x4B, VK_KEYPAD_ENTER = 0x4C,
    VK_KEYPAD_MINUS = 0x4E, VK_KEYPAD_EQUALS = 0x51,
    VK_KEYPAD_0 = 0x52, VK_KEYPAD_1 = 0x53, VK_KEYPAD_2 = 0x54, VK_KEYPAD_3 = 0x55,
    VK_KEYPAD_4 = 0x56, VK_KEYPAD_5 = 0x57, VK_KEYPAD_6 = 0x58, VK_KEYPAD_7 = 0x59,
    VK_KEYPAD_8 = 0x5B, VK_KEYPAD_9 = 0x5C,
    VK_F5 = 0x60, VK_F6 = 0x61, VK_F7 = 0x62, VK_F3 = 0x63, VK_F8 = 0x64, VK_F9 = 0x65,
    VK_F11 = 0x67, VK_F10 = 0x6D, VK_F12 = 0x6F,
    VK_INSERT = 0x72, VK_HOME = 0x73, VK_PAGEUP = 0x74, VK_FORWARDDELETE = 0x75,
    VK_F4 = 0x76, VK_END = 0x77, VK_F2 = 0x78, VK_PAGEDOWN = 0x79, VK_F1 = 0x7A,
    VK_LEFT = 0x7B, VK_RIGHT = 0x7C, VK_DOWN = 0x7D, VK_UP = 0x7E
};

// ---------------------------------------------------------------------------------------
// Objective-C side
// ---------------------------------------------------------------------------------------

@class CrystalOTCView;

struct CocoaCursorState
{
    std::vector<NSCursor*> frames;
    std::vector<int> delays;
};

struct CocoaWindowImpl
{
    NSWindow* window = nil;
    NSTextField* titleLabel = nil;
    CrystalOTCView* view = nil;
    NSObject* windowDelegate = nil;
    NSObject* appDelegate = nil;
    CAMetalLayer* layer = nil;
    id<MTLDevice> device = nil;
    id<MTLCommandQueue> queue = nil;

    std::vector<CocoaCursorState> cursors;
    int currentCursorId = -1;
    size_t currentCursorFrame = 0;
    ticks_t cursorFrameStartedAt = 0;
    bool mouseHidden = false;
};

@interface CrystalOTCView : NSView <NSTextInputClient>
{
@public
    CocoaWindow* owner;
}
@end

@interface CrystalOTCWindowDelegate : NSObject <NSWindowDelegate>
{
@public
    CocoaWindow* owner;
}
@end

@interface CrystalOTCAppDelegate : NSObject <NSApplicationDelegate>
{
@public
    CocoaWindow* owner;
}
@end

@implementation CrystalOTCView

// The engine is top-left origin, y down (see X11Window's mouse handling and the projection
// matrix in Painter). A flipped view means no per-event y arithmetic anywhere below.
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (BOOL)wantsUpdateLayer { return YES; }

- (void)keyDown:(NSEvent*)event
{
    if (!owner)
        return;
    // isARepeat is dropped: PlatformWindow synthesises its own repeat from fireKeysPress(),
    // and letting the OS repeat through would double it.
    if (![event isARepeat])
        owner->handleKey([event keyCode], true,
                         ([event modifierFlags] & NSEventModifierFlagCommand) != 0);

    // Routes to insertText:replacementRange: below, and gives dead keys and IME candidate
    // windows a chance to compose. This is the NSTextInputClient counterpart of X11's XIC.
    [self interpretKeyEvents:@[event]];
}

- (void)keyUp:(NSEvent*)event
{
    if (owner)
        owner->handleKey([event keyCode], false);
}

- (void)flagsChanged:(NSEvent*)event
{
    if (owner)
        owner->handleFlagsChanged(static_cast<unsigned long>([event modifierFlags]));
}

- (void)mouseDown:(NSEvent*)event { if (owner) owner->handleMouseButton(0, true); }
- (void)mouseUp:(NSEvent*)event { if (owner) owner->handleMouseButton(0, false); }
- (void)rightMouseDown:(NSEvent*)event { if (owner) owner->handleMouseButton(1, true); }
- (void)rightMouseUp:(NSEvent*)event { if (owner) owner->handleMouseButton(1, false); }
- (void)otherMouseDown:(NSEvent*)event { if (owner) owner->handleMouseButton(2, true); }
- (void)otherMouseUp:(NSEvent*)event { if (owner) owner->handleMouseButton(2, false); }

- (void)mouseMoved:(NSEvent*)event { [self forwardMouseMove:event]; }
- (void)mouseDragged:(NSEvent*)event { [self forwardMouseMove:event]; }
- (void)rightMouseDragged:(NSEvent*)event { [self forwardMouseMove:event]; }
- (void)otherMouseDragged:(NSEvent*)event { [self forwardMouseMove:event]; }

- (void)forwardMouseMove:(NSEvent*)event
{
    if (!owner)
        return;
    const NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    owner->handleMouseMove(p.x, p.y);
}

- (void)scrollWheel:(NSEvent*)event
{
    if (!owner)
        return;
    double delta = [event scrollingDeltaY];
    if ([event hasPreciseScrollingDeltas])
        delta *= 0.1; // trackpad deltas are in points, wheel deltas in lines
    owner->handleScroll(delta);
}

// --- NSTextInputClient. Only the insertion path is meaningful here: the client has no
// --- marked-text UI, so composition is accepted but never displayed inline.
- (void)insertText:(id)string replacementRange:(NSRange)replacementRange
{
    if (!owner)
        return;
    NSString* text = [string isKindOfClass:[NSAttributedString class]] ? [string string] : string;
    if ([text length] == 0)
        return;
    owner->handleTextInput(std::string([text UTF8String] ?: ""));
}

- (void)doCommandBySelector:(SEL)selector { /* handled by keyDown: */ }
- (void)setMarkedText:(id)string selectedRange:(NSRange)r replacementRange:(NSRange)rr {}
- (void)unmarkText {}
- (NSRange)selectedRange { return NSMakeRange(NSNotFound, 0); }
- (NSRange)markedRange { return NSMakeRange(NSNotFound, 0); }
- (BOOL)hasMarkedText { return NO; }
- (NSAttributedString*)attributedSubstringForProposedRange:(NSRange)r actualRange:(NSRangePointer)ar { return nil; }
- (NSArray<NSAttributedStringKey>*)validAttributesForMarkedText { return @[]; }
- (NSRect)firstRectForCharacterRange:(NSRange)r actualRange:(NSRangePointer)ar { return NSZeroRect; }
- (NSUInteger)characterIndexForPoint:(NSPoint)p { return NSNotFound; }

@end

@implementation CrystalOTCWindowDelegate

- (void)windowDidResize:(NSNotification*)n { if (owner) owner->onWindowResized(); }
- (void)windowDidMove:(NSNotification*)n { if (owner) owner->onWindowMoved(); }
- (void)windowDidBecomeKey:(NSNotification*)n { if (owner) owner->onWindowFocusChanged(true); }
- (void)windowDidResignKey:(NSNotification*)n { if (owner) owner->onWindowFocusChanged(false); }
- (void)windowDidChangeBackingProperties:(NSNotification*)n { if (owner) owner->onBackingPropertiesChanged(); }
- (void)windowDidEnterFullScreen:(NSNotification*)n { if (owner) owner->onWindowResized(); }
- (void)windowDidExitFullScreen:(NSNotification*)n { if (owner) owner->onWindowResized(); }

- (BOOL)windowShouldClose:(NSWindow*)sender
{
    // Never let AppKit destroy the window. The client tears it down in g_window.terminate(),
    // which runs after Lua shutdown, config save and the graphics teardown; destroying the
    // NSWindow here would pull the drawable out from under a still-running frame.
    if (owner)
        owner->onWindowCloseRequested();
    return NO;
}

@end

@implementation CrystalOTCAppDelegate

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender
{
    // Same reasoning as windowShouldClose:. Returning NSTerminateNow would exit() straight
    // out of AppKit and skip the client's whole shutdown chain.
    if (owner)
        owner->onWindowCloseRequested();
    return NSTerminateCancel;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender { return NO; }

@end

// ---------------------------------------------------------------------------------------
// C++ side
// ---------------------------------------------------------------------------------------

CocoaWindow::CocoaWindow()
{
    m_impl = new CocoaWindowImpl();

    m_minimumSize = Size(600, 480);
    m_size = Size(600, 480);

    m_keyMap[VK_ESCAPE] = Fw::KeyEscape;
    m_keyMap[VK_TAB] = Fw::KeyTab;
    m_keyMap[VK_RETURN] = Fw::KeyEnter;
    m_keyMap[VK_KEYPAD_ENTER] = Fw::KeyEnter;
    m_keyMap[VK_BACKSPACE] = Fw::KeyBackspace;
    m_keyMap[VK_FORWARDDELETE] = Fw::KeyDelete;
    m_keyMap[VK_INSERT] = Fw::KeyInsert;
    m_keyMap[VK_HOME] = Fw::KeyHome;
    m_keyMap[VK_END] = Fw::KeyEnd;
    m_keyMap[VK_PAGEUP] = Fw::KeyPageUp;
    m_keyMap[VK_PAGEDOWN] = Fw::KeyPageDown;
    m_keyMap[VK_UP] = Fw::KeyUp;
    m_keyMap[VK_DOWN] = Fw::KeyDown;
    m_keyMap[VK_LEFT] = Fw::KeyLeft;
    m_keyMap[VK_RIGHT] = Fw::KeyRight;
    m_keyMap[VK_CAPSLOCK] = Fw::KeyCapsLock;
    m_keyMap[VK_SPACE] = Fw::KeySpace;

    // Both physical sides collapse onto one Fw::Key, matching X11Window.
    m_keyMap[VK_CONTROL] = Fw::KeyCtrl;
    m_keyMap[VK_RIGHTCONTROL] = Fw::KeyCtrl;
    m_keyMap[VK_SHIFT] = Fw::KeyShift;
    m_keyMap[VK_RIGHTSHIFT] = Fw::KeyShift;
    m_keyMap[VK_OPTION] = Fw::KeyAlt;
    m_keyMap[VK_RIGHTOPTION] = Fw::KeyAlt;
    m_keyMap[VK_COMMAND] = Fw::KeyMeta;

    m_keyMap[VK_0] = Fw::Key0; m_keyMap[VK_1] = Fw::Key1; m_keyMap[VK_2] = Fw::Key2;
    m_keyMap[VK_3] = Fw::Key3; m_keyMap[VK_4] = Fw::Key4; m_keyMap[VK_5] = Fw::Key5;
    m_keyMap[VK_6] = Fw::Key6; m_keyMap[VK_7] = Fw::Key7; m_keyMap[VK_8] = Fw::Key8;
    m_keyMap[VK_9] = Fw::Key9;

    m_keyMap[VK_A] = Fw::KeyA; m_keyMap[VK_B] = Fw::KeyB; m_keyMap[VK_C] = Fw::KeyC;
    m_keyMap[VK_D] = Fw::KeyD; m_keyMap[VK_E] = Fw::KeyE; m_keyMap[VK_F] = Fw::KeyF;
    m_keyMap[VK_G] = Fw::KeyG; m_keyMap[VK_H] = Fw::KeyH; m_keyMap[VK_I] = Fw::KeyI;
    m_keyMap[VK_J] = Fw::KeyJ; m_keyMap[VK_K] = Fw::KeyK; m_keyMap[VK_L] = Fw::KeyL;
    m_keyMap[VK_M] = Fw::KeyM; m_keyMap[VK_N] = Fw::KeyN; m_keyMap[VK_O] = Fw::KeyO;
    m_keyMap[VK_P] = Fw::KeyP; m_keyMap[VK_Q] = Fw::KeyQ; m_keyMap[VK_R] = Fw::KeyR;
    m_keyMap[VK_S] = Fw::KeyS; m_keyMap[VK_T] = Fw::KeyT; m_keyMap[VK_U] = Fw::KeyU;
    m_keyMap[VK_V] = Fw::KeyV; m_keyMap[VK_W] = Fw::KeyW; m_keyMap[VK_X] = Fw::KeyX;
    m_keyMap[VK_Y] = Fw::KeyY; m_keyMap[VK_Z] = Fw::KeyZ;

    m_keyMap[VK_MINUS] = Fw::KeyMinus;
    m_keyMap[VK_EQUAL] = Fw::KeyEqual;
    m_keyMap[VK_LEFTBRACKET] = Fw::KeyLeftBracket;
    m_keyMap[VK_RIGHTBRACKET] = Fw::KeyRightBracket;
    m_keyMap[VK_BACKSLASH] = Fw::KeyBackslash;
    m_keyMap[VK_SEMICOLON] = Fw::KeySemicolon;
    m_keyMap[VK_APOSTROPHE] = Fw::KeyApostrophe;
    m_keyMap[VK_GRAVE] = Fw::KeyGrave;
    m_keyMap[VK_COMMA] = Fw::KeyComma;
    m_keyMap[VK_PERIOD] = Fw::KeyPeriod;
    m_keyMap[VK_SLASH] = Fw::KeySlash;

    m_keyMap[VK_KEYPAD_0] = Fw::KeyNumpad0; m_keyMap[VK_KEYPAD_1] = Fw::KeyNumpad1;
    m_keyMap[VK_KEYPAD_2] = Fw::KeyNumpad2; m_keyMap[VK_KEYPAD_3] = Fw::KeyNumpad3;
    m_keyMap[VK_KEYPAD_4] = Fw::KeyNumpad4; m_keyMap[VK_KEYPAD_5] = Fw::KeyNumpad5;
    m_keyMap[VK_KEYPAD_6] = Fw::KeyNumpad6; m_keyMap[VK_KEYPAD_7] = Fw::KeyNumpad7;
    m_keyMap[VK_KEYPAD_8] = Fw::KeyNumpad8; m_keyMap[VK_KEYPAD_9] = Fw::KeyNumpad9;
    m_keyMap[VK_KEYPAD_DECIMAL] = Fw::KeyPeriod;
    m_keyMap[VK_KEYPAD_PLUS] = Fw::KeyPlus;
    m_keyMap[VK_KEYPAD_MINUS] = Fw::KeyMinus;
    m_keyMap[VK_KEYPAD_MULTIPLY] = Fw::KeyAsterisk;
    m_keyMap[VK_KEYPAD_DIVIDE] = Fw::KeySlash;
    m_keyMap[VK_KEYPAD_EQUALS] = Fw::KeyEqual;
    m_keyMap[VK_KEYPAD_CLEAR] = Fw::KeyNumLock;

    m_keyMap[VK_F1] = Fw::KeyF1; m_keyMap[VK_F2] = Fw::KeyF2; m_keyMap[VK_F3] = Fw::KeyF3;
    m_keyMap[VK_F4] = Fw::KeyF4; m_keyMap[VK_F5] = Fw::KeyF5; m_keyMap[VK_F6] = Fw::KeyF6;
    m_keyMap[VK_F7] = Fw::KeyF7; m_keyMap[VK_F8] = Fw::KeyF8; m_keyMap[VK_F9] = Fw::KeyF9;
    m_keyMap[VK_F10] = Fw::KeyF10; m_keyMap[VK_F11] = Fw::KeyF11; m_keyMap[VK_F12] = Fw::KeyF12;
}

CocoaWindow::~CocoaWindow()
{
    delete m_impl;
    m_impl = nullptr;
}

void CocoaWindow::init()
{
    @autoreleasepool {
        internalCreateApplication();
        internalCreateWindow();
    }
}

void CocoaWindow::internalCreateApplication()
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    auto* delegate = [[CrystalOTCAppDelegate alloc] init];
    delegate->owner = this;
    m_impl->appDelegate = delegate;
    [NSApp setDelegate:(id<NSApplicationDelegate>)delegate];

    // Without a menu bar the application cannot become active properly and Cmd-Q is dead.
    //
    // The item set mirrors the app menu Qt's QCocoaMenuLoader installs, which is what the
    // official client ends up with on macOS: Hide, Hide Others, Show All, Quit. That is the
    // parity target, and it is also the reason Minimize (Cmd-M), Zoom and Close (Cmd-W) are
    // deliberately absent -- the official client ships no Window menu, and adding one here
    // would silently shadow the default "Ctrl+M" keybind, which resolves to Cmd-M on macOS.
    //
    // Cmd-H is the one collision we accept, because the official client has it too: its
    // shipped "Ctrl+H" binding (Open Help Channel) is likewise shadowed by Hide on macOS.
    //
    // No Edit menu either, and that one is load-bearing rather than cosmetic. Menu key
    // equivalents are matched before the event reaches the view, so an Edit menu carrying
    // Cmd-C/V/X/A would swallow those and route them to copy:/paste:/cut:/selectAll: on the
    // first responder -- selectors the engine does not implement. Leaving them out lets the
    // events fall through to keyDown: and into UITextEdit, which already handles them.
    NSMenu* menuBar = [[NSMenu alloc] init];
    NSMenuItem* appMenuItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appMenuItem];
    NSMenu* appMenu = [[NSMenu alloc] init];
    NSString* appName = [[NSProcessInfo processInfo] processName];

    // These three act on NSApplication itself, so they need no cooperation from the engine.
    [appMenu addItemWithTitle:[@"Hide " stringByAppendingString:appName]
                       action:@selector(hide:)
                keyEquivalent:@"h"];
    NSMenuItem* hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:NSEventModifierFlagOption | NSEventModifierFlagCommand];
    [appMenu addItemWithTitle:@"Show All"
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];

    // The Quit item is routed through applicationShouldTerminate:, which cancels and hands
    // the request to the client instead.
    [appMenu addItemWithTitle:[@"Quit " stringByAppendingString:appName]
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [NSApp setMainMenu:menuBar];

    // finishLaunching, not run: the client owns the main loop and pumps AppKit from poll().
    [NSApp finishLaunching];
    [NSApp activateIgnoringOtherApps:YES];
}

void CocoaWindow::internalCreateWindow()
{
    const NSRect content = NSMakeRect(m_position.x, m_position.y, m_size.width(), m_size.height());
    const NSWindowStyleMask style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                    NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

    m_impl->window = [[NSWindow alloc] initWithContentRect:content
                                                styleMask:style
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    [m_impl->window setReleasedWhenClosed:NO];
    [m_impl->window setAcceptsMouseMovedEvents:YES];
    [m_impl->window setRestorable:NO];
    [m_impl->window setContentMinSize:NSMakeSize(m_minimumSize.width(), m_minimumSize.height())];

    // AppKit left-aligns the native title in the modern compact title bar used by this
    // window. The official client keeps its product title centered, so retain the native
    // title for accessibility/window management but render a centered title-bar label.
    [m_impl->window setTitleVisibility:NSWindowTitleHidden];
    NSView* titleBar = [[m_impl->window standardWindowButton:NSWindowCloseButton] superview];
    if (titleBar) {
        NSTextField* titleLabel = [NSTextField labelWithString:@""];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.alignment = NSTextAlignmentCenter;
        titleLabel.font = [NSFont titleBarFontOfSize:0.0];
        titleLabel.textColor = [NSColor secondaryLabelColor];
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [titleBar addSubview:titleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.centerXAnchor constraintEqualToAnchor:titleBar.centerXAnchor],
            [titleLabel.centerYAnchor constraintEqualToAnchor:
                [m_impl->window standardWindowButton:NSWindowCloseButton].centerYAnchor],
            [titleLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:
                [m_impl->window standardWindowButton:NSWindowZoomButton].trailingAnchor constant:12.0],
            [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:titleBar.trailingAnchor constant:-12.0]
        ]];
        m_impl->titleLabel = titleLabel;
    }

    auto* view = [[CrystalOTCView alloc] initWithFrame:content];
    view->owner = this;
    m_impl->view = view;

    m_impl->device = MTLCreateSystemDefaultDevice();
    if (!m_impl->device)
        g_logger.fatal("no Metal device is available on this machine");

    m_impl->layer = [CAMetalLayer layer];
    m_impl->layer.device = m_impl->device;
    m_impl->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    internalApplyPresentationColorSpace();
    m_impl->layer.framebufferOnly = YES;
    m_impl->layer.opaque = YES;

    [view setLayer:m_impl->layer];
    [view setWantsLayer:YES];
    [m_impl->window setContentView:view];
    [m_impl->window makeFirstResponder:view];

    auto* windowDelegate = [[CrystalOTCWindowDelegate alloc] init];
    windowDelegate->owner = this;
    m_impl->windowDelegate = windowDelegate;
    [m_impl->window setDelegate:(id<NSWindowDelegate>)windowDelegate];

    m_impl->queue = [m_impl->device newCommandQueue];

    // m_size must be in backing pixels and the device pixel ratio must be set before
    // GraphicalApplication::init calls resize(g_window.getSize()); see the header. Note this
    // sets the RATIO, not the density: since the two were split, m_displayDensity is the
    // product of this and the user's HUD scale, and writing it directly would discard theirs.
    m_backingScale = static_cast<float>([m_impl->window backingScaleFactor]);
    setDevicePixelRatio(m_backingScale);

    const NSRect backing = [view convertRectToBacking:[view bounds]];
    m_size = Size(static_cast<int>(backing.size.width), static_cast<int>(backing.size.height));
    m_impl->layer.contentsScale = m_backingScale;
    m_impl->layer.drawableSize = CGSizeMake(backing.size.width, backing.size.height);

    updateUnmaximizedCoords();
}

void CocoaWindow::terminate()
{
    // No g_mainDispatcher here: by this point Application::deinit has shut every dispatcher
    // down and addEvent is a silent no-op (see the header).
    @autoreleasepool {
        if (m_impl->mouseHidden) {
            [NSCursor unhide];
            m_impl->mouseHidden = false;
        }

        m_impl->cursors.clear();

        if (m_impl->window) {
            [m_impl->window setDelegate:nil];
            [m_impl->window orderOut:nil];
            m_impl->window = nil;
        }
        m_impl->titleLabel = nil;
        if (m_impl->view) {
            m_impl->view->owner = nullptr;
            m_impl->view = nil;
        }

        m_impl->layer = nil;
        m_impl->queue = nil;
        m_impl->device = nil;

        if (m_impl->appDelegate) {
            [NSApp setDelegate:nil];
            m_impl->appDelegate = nil;
        }
        m_impl->windowDelegate = nil;
    }

    m_visible = false;
    m_focused = false;
}

void CocoaWindow::internalPumpEvents()
{
    while (true) {
        NSEvent* event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                            untilDate:[NSDate distantPast]
                                               inMode:NSDefaultRunLoopMode
                                              dequeue:YES];
        if (!event)
            break;
        [NSApp sendEvent:event];
    }
    [NSApp updateWindows];
}

void CocoaWindow::poll()
{
    @autoreleasepool {
        internalPumpEvents();

        if (m_impl->currentCursorId >= 0 &&
            m_impl->currentCursorId < static_cast<int>(m_impl->cursors.size())) {
            auto& cursor = m_impl->cursors[m_impl->currentCursorId];
            if (cursor.frames.size() > 1) {
                const auto now = g_clock.millis();
                const int delay = cursor.delays[m_impl->currentCursorFrame];
                if (now - m_impl->cursorFrameStartedAt >= delay) {
                    m_impl->currentCursorFrame = (m_impl->currentCursorFrame + 1) % cursor.frames.size();
                    m_impl->cursorFrameStartedAt = now;
                    [cursor.frames[m_impl->currentCursorFrame] set];
                }
            }
        }

        // NSPasteboard is main-thread work, but getClipboardText() is called from the map
        // thread (uitextedit). Snapshot it here instead.
        //
        // Gated on changeCount, and that gate is load-bearing rather than an optimisation.
        // setClipboardText() updates m_clipboardCache immediately but can only write the board
        // itself from a queued main-thread event; this loop runs every frame, so an
        // unconditional re-read would overwrite the just-cut text with the board's previous
        // contents before that write ever landed -- Cmd+X followed by Cmd+V pasted whatever
        // had been on the clipboard beforehand.
        NSPasteboard* board = [NSPasteboard generalPasteboard];
        if (const long changeCount = static_cast<long>([board changeCount]);
            changeCount != m_pasteboardChangeCount) {
            m_pasteboardChangeCount = changeCount;
            NSString* pasted = [board stringForType:NSPasteboardTypeString];
            m_clipboardCache = pasted ? stdext::utf8_to_latin1(std::string([pasted UTF8String] ?: "")) : "";
        }

        internalApplyPendingGeometry();

        if (m_closeRequested) {
            m_closeRequested = false;
            if (m_onClose)
                m_onClose();
        }
    }

    // Coalesced to one call per frame, matching X11Window: a live resize drag produces a
    // storm of windowDidResize: and the client must not re-lay-out the UI for each one.
    if (m_pendingResize) {
        m_pendingResize = false;
        m_size = m_pendingSize;
        if (m_onResize)
            m_onResize(m_size);
    }

    fireKeysPress();
}

void CocoaWindow::internalApplyPendingGeometry()
{
    if (!m_impl->view || !m_impl->window)
        return;

    const NSRect backing = [m_impl->view convertRectToBacking:[m_impl->view bounds]];
    const Size drawable(static_cast<int>(backing.size.width), static_cast<int>(backing.size.height));

    if (drawable.width() > 0 && drawable.height() > 0 && drawable != m_size) {
        m_pendingSize = drawable;
        m_pendingResize = true;
        m_impl->layer.drawableSize = CGSizeMake(backing.size.width, backing.size.height);
    }

    const NSRect frame = [m_impl->window frame];
    m_position = Point(static_cast<int>(frame.origin.x), static_cast<int>(frame.origin.y));
    m_maximized = [m_impl->window isZoomed];
    m_visible = [m_impl->window isVisible];
    if (!m_fullscreen && !m_maximized)
        updateUnmaximizedCoords();
}

NativeSurface CocoaWindow::getNativeSurface() const
{
    if (!m_impl || !m_impl->layer || !m_impl->device)
        return {};

    // This translation unit compiles without ARC (nothing in CMake passes -fobjc-arc), so an
    // Objective-C pointer converts to void* by a plain cast; a __bridge cast would not even
    // compile here. The feature test is there so that turning ARC on later is a build
    // configuration change rather than a silent ownership bug.
#if __has_feature(objc_arc)
    return { NativeSurfaceType::CocoaMetalLayer, (__bridge void*)m_impl->layer, (__bridge void*)m_impl->device };
#else
    return { NativeSurfaceType::CocoaMetalLayer, (void*)m_impl->layer, (void*)m_impl->device };
#endif
}

void CocoaWindow::swapBuffers()
{
    // Presentation of last resort. A render backend that acquires the drawable itself also
    // presents it - it has to, since only the command buffer that rendered into a drawable may
    // present it - and claims ownership here so this does not overwrite its frame. What remains
    // is the Phase 1 acquire-clear-present, which is what runs before any backend exists and
    // whenever one declines a frame: a navy screen is a visible, diagnosable state.
    if (m_presentationOwned)
        return;

    @autoreleasepool {
        if (!m_impl->layer || !m_impl->queue)
            return;

        id<CAMetalDrawable> drawable = [m_impl->layer nextDrawable];
        if (!drawable)
            return; // window server starvation or a zero-sized window: skip the frame

        MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        // Deliberately the same navy the Windows Vulkan fallback uses, so a frame drawn by
        // this path is identifiable by eye.
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0.05, 0.10, 0.25, 1.0);

        id<MTLCommandBuffer> commands = [m_impl->queue commandBuffer];
        [commands setLabel:@"CrystalOTC clear"];
        id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
        [encoder setLabel:@"CrystalOTC clear pass"];
        [encoder endEncoding];
        [commands presentDrawable:drawable];
        [commands commit];
    }
}

// --- window state ----------------------------------------------------------------------

void CocoaWindow::move(const Point& pos)
{
    g_mainDispatcher.addEvent([this, pos] {
        @autoreleasepool {
            m_position = pos;
            if (m_impl->window)
                [m_impl->window setFrameOrigin:NSMakePoint(pos.x, pos.y)];
        }
    });
}

void CocoaWindow::resize(const Size& size)
{
    if (size.width() < m_minimumSize.width() || size.height() < m_minimumSize.height())
        return;

    g_mainDispatcher.addEvent([this, size] {
        @autoreleasepool {
            if (!m_impl->window)
                return;
            // The caller speaks in backing pixels (m_size); NSWindow speaks in points.
            const CGFloat scale = m_backingScale > 0.f ? m_backingScale : 1.f;
            [m_impl->window setContentSize:NSMakeSize(size.width() / scale, size.height() / scale)];
        }
    });
}

void CocoaWindow::show()
{
    g_mainDispatcher.addEvent([this] {
        @autoreleasepool {
            if (!m_impl->window)
                return;
            [m_impl->window makeKeyAndOrderFront:nil];
            [NSApp activateIgnoringOtherApps:YES];
            m_visible = true;
        }
    });
}

void CocoaWindow::hide()
{
    g_mainDispatcher.addEvent([this] {
        @autoreleasepool {
            if (m_impl->window)
                [m_impl->window orderOut:nil];
            m_visible = false;
        }
    });
}

void CocoaWindow::maximize()
{
    g_mainDispatcher.addEvent([this] {
        @autoreleasepool {
            if (m_impl->window && ![m_impl->window isZoomed])
                [m_impl->window zoom:nil];
            m_maximized = true;
        }
    });
}

// The renderer performs legacy UI blending on raw sRGB bytes, but the compositor still needs to
// be told how to present them. Tagging the layer sRGB is the accurate choice: the artwork is
// authored and tagged sRGB, so Core Animation colour-matches it into the display's space and it
// looks the way its artists intended on any panel. The official client leaves its layer
// unmatched, which on a Display P3 Mac pushes those same bytes across a wider gamut and reads as
// roughly 13% more saturated - measurably wrong, but what players comparing the two side by side
// expect to see. m_vividColors picks the official client's unmanaged presentation instead.
//
// Per CAMetalLayer.h: "If nil, no colormatching occurs." Both branches are no-ops on an
// sRGB-gamut display, where the colour match is the identity.
void CocoaWindow::internalApplyPresentationColorSpace()
{
    if (!m_impl || !m_impl->layer)
        return;

    if (m_vividColors) {
        m_impl->layer.colorspace = nil;
        return;
    }

    CGColorSpaceRef presentationColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    m_impl->layer.colorspace = presentationColorSpace;
    CGColorSpaceRelease(presentationColorSpace);
}

void CocoaWindow::setVividColors(const bool enable)
{
    if (m_vividColors == enable)
        return;

    m_vividColors = enable;
    internalApplyPresentationColorSpace();
}

void CocoaWindow::setFullscreen(const bool fullscreen)
{
    g_mainDispatcher.addEvent([this, fullscreen] {
        @autoreleasepool {
            if (!m_impl->window)
                return;
            const bool isFullscreen = ([m_impl->window styleMask] & NSWindowStyleMaskFullScreen) != 0;
            if (isFullscreen != fullscreen)
                [m_impl->window toggleFullScreen:nil];
            m_fullscreen = fullscreen;
        }
    });
}

void CocoaWindow::setTitle(const std::string_view title)
{
    const std::string copy{ title };
    g_mainDispatcher.addEvent([this, copy] {
        @autoreleasepool {
            if (m_impl->window)
                [m_impl->window setTitle:[NSString stringWithUTF8String:stdext::latin1_to_utf8(copy).c_str()]];
            if (m_impl->titleLabel)
                [m_impl->titleLabel setStringValue:[NSString stringWithUTF8String:stdext::latin1_to_utf8(copy).c_str()]];
        }
    });
}

void CocoaWindow::setMinimumSize(const Size& minimumSize)
{
    // X11Window never assigns m_minimumSize here, which leaves resize() and
    // getMinimumSize() reading the constructor default forever. Assign it.
    m_minimumSize = minimumSize;
    g_mainDispatcher.addEvent([this, minimumSize] {
        @autoreleasepool {
            if (!m_impl->window)
                return;
            const CGFloat scale = m_backingScale > 0.f ? m_backingScale : 1.f;
            [m_impl->window setContentMinSize:NSMakeSize(minimumSize.width() / scale,
                                                        minimumSize.height() / scale)];
        }
    });
}

void CocoaWindow::setVerticalSync(const bool enable)
{
    m_vsync = enable;
    g_mainDispatcher.addEvent([this, enable] {
        @autoreleasepool {
            if (m_impl->layer)
                m_impl->layer.displaySyncEnabled = enable ? YES : NO;
        }
    });
}

void CocoaWindow::setIcon(const std::string& iconFile)
{
    // A bundled app takes its icon from Info.plist/CFBundleIconFile; this only affects the
    // Dock tile for an unbundled binary, which is what a development build runs as.
    g_mainDispatcher.addEvent([iconFile] {
        @autoreleasepool {
            const auto& image = Image::load(iconFile);
            if (!image || image->getBpp() != 4)
                return;

            const auto size = image->getSize();
            NSBitmapImageRep* rep =
                [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
                                                       pixelsWide:size.width()
                                                       pixelsHigh:size.height()
                                                    bitsPerSample:8
                                                  samplesPerPixel:4
                                                         hasAlpha:YES
                                                         isPlanar:NO
                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                      bytesPerRow:size.width() * 4
                                                     bitsPerPixel:32];
            memcpy([rep bitmapData], image->getPixelData(), size.area() * 4);

            NSImage* icon = [[NSImage alloc] initWithSize:NSMakeSize(size.width(), size.height())];
            [icon addRepresentation:rep];
            [NSApp setApplicationIconImage:icon];
        }
    });
}

// --- cursors ---------------------------------------------------------------------------

int CocoaWindow::internalLoadMouseCursor(const ImagePtr& image, const Point& hotSpot)
{
    @autoreleasepool {
        CocoaCursorState cursorState;

        const auto appendFrame = [&](const ImagePtr& frame, const Rect& sourceRect, const int delay) {
            NSBitmapImageRep* rep =
                [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr
                                                       pixelsWide:sourceRect.width()
                                                       pixelsHigh:sourceRect.height()
                                                    bitsPerSample:8
                                                  samplesPerPixel:4
                                                         hasAlpha:YES
                                                         isPlanar:NO
                                                   colorSpaceName:NSDeviceRGBColorSpace
                                                      bytesPerRow:sourceRect.width() * 4
                                                     bitsPerPixel:32];

            auto* destination = [rep bitmapData];
            const auto* source = frame->getPixelData();
            const int sourceStride = frame->getWidth() * 4;
            const int destinationStride = sourceRect.width() * 4;
            for (int y = 0; y < sourceRect.height(); ++y) {
                memcpy(destination + y * destinationStride,
                       source + (sourceRect.y() + y) * sourceStride + sourceRect.x() * 4,
                       destinationStride);
            }

            // Unlike X11's 1-bit pixmap cursors, this keeps the full RGBA image.
            NSImage* cursorImage = [[NSImage alloc]
                initWithSize:NSMakeSize(sourceRect.width(), sourceRect.height())];
            [cursorImage addRepresentation:rep];

            cursorState.frames.push_back([[NSCursor alloc]
                initWithImage:cursorImage hotSpot:NSMakePoint(hotSpot.x, hotSpot.y)]);
            cursorState.delays.push_back(delay);
        };

        if (image->isAnimated()) {
            for (const auto& frame : image->getAnimation())
                appendFrame(frame.image, Rect(Point(), frame.image->getSize()), frame.delay);
        } else {
            const auto size = image->getSize();
            // The official client stores its animated cursors as horizontal square-frame
            // strips (for example cursor-walk.png is 256x32). AppKit does not interpret
            // sprite sheets, so handing it the full image creates one malformed cursor.
            // Split those strips here and let poll() advance the active NSCursor.
            const bool isHorizontalStrip = size.height() > 0 && size.width() >= size.height() * 2 &&
                                           size.width() % size.height() == 0;
            if (isHorizontalStrip) {
                const int frameSize = size.height();
                for (int x = 0; x < size.width(); x += frameSize)
                    appendFrame(image, Rect(x, 0, frameSize, frameSize), 100);
            } else {
                appendFrame(image, Rect(Point(), size), 0);
            }
        }

        m_impl->cursors.push_back(std::move(cursorState));
        return static_cast<int>(m_impl->cursors.size()) - 1;
    }
}

void CocoaWindow::setMouseCursor(const int cursorId)
{
    if (cursorId < 0)
        return;

    g_mainDispatcher.addEvent([this, cursorId] {
        @autoreleasepool {
            if (cursorId >= static_cast<int>(m_impl->cursors.size()))
                return;
            if (m_impl->mouseHidden) {
                [NSCursor unhide];
                m_impl->mouseHidden = false;
            }
            auto& cursor = m_impl->cursors[cursorId];
            if (cursor.frames.empty())
                return;

            // Map hover updates can select the same semantic cursor again whenever the
            // pointer crosses a tile boundary. Do not restart an animation in that case,
            // or a moving pointer remains stuck near its first frame.
            if (m_impl->currentCursorId != cursorId) {
                m_impl->currentCursorId = cursorId;
                m_impl->currentCursorFrame = 0;
                m_impl->cursorFrameStartedAt = g_clock.millis();
            }
            [cursor.frames[m_impl->currentCursorFrame] set];
        }
    });
}

void CocoaWindow::restoreMouseCursor()
{
    g_mainDispatcher.addEvent([this] {
        @autoreleasepool {
            if (m_impl->mouseHidden) {
                [NSCursor unhide];
                m_impl->mouseHidden = false;
            }
            m_impl->currentCursorId = -1;
            [[NSCursor arrowCursor] set];
        }
    });
}

void CocoaWindow::showMouse()
{
    g_mainDispatcher.addEvent([this] {
        @autoreleasepool {
            if (m_impl->mouseHidden) {
                [NSCursor unhide];
                m_impl->mouseHidden = false;
            }
        }
    });
}

void CocoaWindow::hideMouse()
{
    g_mainDispatcher.addEvent([this] {
        @autoreleasepool {
            // hide/unhide are counted; guarding keeps them balanced.
            if (!m_impl->mouseHidden) {
                [NSCursor hide];
                m_impl->mouseHidden = true;
            }
        }
    });
}

// --- clipboard, queries ------------------------------------------------------------------

void CocoaWindow::setClipboardText(const std::string_view text)
{
    const std::string copy{ text };
    m_clipboardCache = copy;
    g_mainDispatcher.addEvent([copy] {
        @autoreleasepool {
            NSPasteboard* board = [NSPasteboard generalPasteboard];
            [board clearContents];
            [board setString:[NSString stringWithUTF8String:stdext::latin1_to_utf8(copy).c_str()]
                     forType:NSPasteboardTypeString];
        }
    });
}

std::string CocoaWindow::getClipboardText()
{
    // Snapshot taken in poll(); see the comment there.
    return m_clipboardCache;
}

Size CocoaWindow::getDisplaySize()
{
    @autoreleasepool {
        NSScreen* screen = m_impl->window ? [m_impl->window screen] : [NSScreen mainScreen];
        if (!screen)
            screen = [NSScreen mainScreen];
        const NSRect frame = [screen frame];
        const CGFloat scale = [screen backingScaleFactor];
        return Size(static_cast<int>(frame.size.width * scale),
                    static_cast<int>(frame.size.height * scale));
    }
}

Size CocoaWindow::getDrawableSize() const
{
    if (!m_impl || !m_impl->layer)
        return m_size;
    const CGSize size = m_impl->layer.drawableSize;
    return Size(static_cast<int>(size.width), static_cast<int>(size.height));
}

std::string CocoaWindow::getPlatformType() { return "Cocoa-Metal"; }

void CocoaWindow::displayFatalError(const std::string_view message)
{
    // Reachable from any thread and from a half-destroyed state (Logger::log at LogFatal
    // calls this and then exit(-1)), so it must not touch m_impl or defer anything.
    const std::string copy{ message };
    @autoreleasepool {
        NSAlert* alert = [[NSAlert alloc] init];
        [alert setAlertStyle:NSAlertStyleCritical];
        [alert setMessageText:@"CrystalOTC - fatal error"];
        [alert setInformativeText:[NSString stringWithUTF8String:copy.c_str()] ?: @"unknown error"];
        [alert addButtonWithTitle:@"Quit"];
        if ([NSThread isMainThread])
            [alert runModal];
    }
}

// --- AppKit callbacks ---------------------------------------------------------------------

void CocoaWindow::onWindowResized() { /* latched in internalApplyPendingGeometry() */ }
void CocoaWindow::onWindowMoved() { /* latched in internalApplyPendingGeometry() */ }

void CocoaWindow::onWindowFocusChanged(const bool focused)
{
    m_focused = focused;
    // Matches X11Window, which releases on both FocusIn and FocusOut: a key held while
    // focus moves would otherwise stay logically down forever. releaseAllKeys() also zeroes
    // keyboardModifiers, so the cached mask has to follow it or the next flagsChanged:
    // would see no transition and never re-apply a modifier still physically held.
    m_modifierFlags = 0;
    releaseAllKeys();
}

void CocoaWindow::onWindowCloseRequested() { m_closeRequested = true; }

void CocoaWindow::onBackingPropertiesChanged()
{
    if (!m_impl->window)
        return;
    const float scale = static_cast<float>([m_impl->window backingScaleFactor]);
    if (scale <= 0.f || scale == m_backingScale)
        return;

    m_backingScale = scale;
    // Only the ratio: a display change must not discard the HUD scale the user chose.
    setDevicePixelRatio(scale);
    if (m_impl->layer)
        m_impl->layer.contentsScale = scale;
    // The new drawable size is picked up by internalApplyPendingGeometry() on the next poll,
    // which also fires the single coalesced m_onResize.
}

// --- input ---------------------------------------------------------------------------------

void CocoaWindow::handleKey(const int virtualKeyCode, const bool pressed, const bool commandHeld)
{
    Fw::Key key = Fw::KeyUnknown;
    if (const auto it = m_keyMap.find(virtualKeyCode); it != m_keyMap.end())
        key = it->second;

    if (!pressed) {
        processKeyUp(key);
        return;
    }

    processKeyDown(key);

    // AppKit does not deliver keyUp: for a key pressed while Command is held -- the release
    // simply never arrives. Without this the key stays logically down in m_keyInfo forever:
    // fireKeysPress() keeps repeating it, so the character turns on the spot while Command is
    // down and then walks away on its own the moment Command is released, because the repeat
    // continues with the modifier gone.
    //
    // Closing the press immediately is right rather than merely expedient: a Command chord on
    // macOS is always a discrete command, never something held, so one press is one action.
    // Keys pressed *before* Command went down are handled in handleFlagsChanged().
    if (commandHeld)
        processKeyUp(key);
}

void CocoaWindow::handleFlagsChanged(const unsigned long modifierFlags)
{
    // Cocoa reports modifiers as a state mask rather than as key events, so the transitions
    // have to be synthesised. This function's job is only to name the physical key that
    // changed; which logical modifier bit that raises is PlatformWindow's decision, and on
    // macOS it swaps Command onto the Ctrl bit and Control onto the Meta bit -- see the
    // table above modifierBitFor() in platformwindow.cpp.
    //
    // The previous mask is the only usable prior state: processKeyDown and processKeyUp
    // return early for modifier keys *before* touching m_keyInfo, so isKeyPressed() reads
    // false for them forever. Comparing against it made every release look like "no
    // change", so modifiers latched on and were never cleared.
    const auto sync = [this](const unsigned long was, const unsigned long now,
                             const unsigned long mask, const Fw::Key key) {
        const bool wasDown = (was & mask) != 0;
        const bool isDown = (now & mask) != 0;
        if (wasDown == isDown)
            return;
        if (isDown)
            processKeyDown(key);
        else
            processKeyUp(key);
    };

    const unsigned long previous = m_modifierFlags;
    m_modifierFlags = modifierFlags;

    sync(previous, modifierFlags, NSEventModifierFlagControl, Fw::KeyCtrl);
    sync(previous, modifierFlags, NSEventModifierFlagShift, Fw::KeyShift);
    sync(previous, modifierFlags, NSEventModifierFlagCommand, Fw::KeyMeta);
    sync(previous, modifierFlags, NSEventModifierFlagOption, Fw::KeyAlt);

    // A key that was already down when Command was pressed still loses its keyUp: if it is
    // released during the Command window, so on the way back out anything still logically
    // held may well be physically up. Let it go. releaseAllPressedKeys() rather than
    // releaseAllKeys() because Shift or Option may genuinely still be down, and zeroing the
    // modifier mask here would drop them with no later transition to put them back.
    if ((previous & NSEventModifierFlagCommand) != 0 && (modifierFlags & NSEventModifierFlagCommand) == 0)
        releaseAllPressedKeys();
}

void CocoaWindow::handleTextInput(const std::string& utf8Text)
{
    if (!m_onInputEvent || utf8Text.empty())
        return;

    // Which modifiers suppress text is genuinely platform-specific, so this deliberately does
    // NOT mirror X11Window's Ctrl|Alt test. On macOS, Option is the compose key -- Opt+O is
    // "o-slash", Opt+E then E is an acute e -- and AppKit has already folded that into the
    // string handed to insertText:, so blocking on the Alt bit would break accented input.
    // Command and Control are the two that never produce text, and after the swap in
    // PlatformWindow::processKeyDown those are the Ctrl and Meta bits respectively.
    if (m_inputEvent.keyboardModifiers & (Fw::KeyboardCtrlModifier | Fw::KeyboardMetaModifier))
        return;

    const std::string text = stdext::utf8_to_latin1(utf8Text);
    if (text.empty() || static_cast<uint8_t>(text[0]) < 32 || static_cast<uint8_t>(text[0]) == 127)
        return;

    m_inputEvent.reset(Fw::KeyTextInputEvent);
    m_inputEvent.keyText = text;
    m_onInputEvent(m_inputEvent);
}

void CocoaWindow::handleMouseButton(const int button, const bool pressed)
{
    Fw::MouseButton mouseButton = Fw::MouseNoButton;
    switch (button) {
        case 0: mouseButton = Fw::MouseLeftButton; break;
        case 1: mouseButton = Fw::MouseRightButton; break;
        case 2: mouseButton = Fw::MouseMidButton; break;
        default: return;
    }

    m_inputEvent.reset();
    m_inputEvent.type = pressed ? Fw::MousePressInputEvent : Fw::MouseReleaseInputEvent;
    m_inputEvent.mouseButton = mouseButton;

    if (pressed) {
        m_mouseButtonStates |= 1u << mouseButton;
    } else {
        // Deferred exactly as X11Window does it, so the state still reads "pressed" while
        // the release handler runs.
        g_dispatcher.addEvent([this, mouseButton] {
            m_mouseButtonStates &= ~(1u << mouseButton);
        });
    }

    if (m_onInputEvent)
        m_onInputEvent(m_inputEvent);
}

void CocoaWindow::handleMouseMove(const double viewX, const double viewY)
{
    // The view is flipped, so these are already top-left origin points. Convert to backing
    // pixels and then divide by the density, matching X11Window's contract that mousePos is
    // in logical units.
    const float density = m_displayDensity > 0.f ? m_displayDensity : 1.f;
    const Point newMousePos(static_cast<int>(viewX * m_backingScale / density),
                            static_cast<int>(viewY * m_backingScale / density));

    m_inputEvent.reset();
    m_inputEvent.type = Fw::MouseMoveInputEvent;
    m_inputEvent.mouseMoved = newMousePos - m_inputEvent.mousePos;
    m_inputEvent.mousePos = newMousePos;

    if (m_onInputEvent)
        m_onInputEvent(m_inputEvent);
}

void CocoaWindow::handleScroll(const double deltaY)
{
    if (deltaY == 0.0)
        return;

    m_inputEvent.reset();
    m_inputEvent.type = Fw::MouseWheelInputEvent;
    // X11Window reports the middle button on wheel events even though nothing was clicked;
    // Lua handlers read it, so keep it.
    m_inputEvent.mouseButton = Fw::MouseMidButton;
    m_inputEvent.wheelDirection = deltaY > 0.0 ? Fw::MouseWheelUp : Fw::MouseWheelDown;

    if (m_onInputEvent)
        m_onInputEvent(m_inputEvent);
}

#endif // CRYSTALOTC_COCOA_WINDOW
