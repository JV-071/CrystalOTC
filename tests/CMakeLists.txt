find_package(GTest CONFIG REQUIRED)

include(GoogleTest)

function(otclient_add_gtest TARGET_NAME)
    add_executable(${TARGET_NAME} ${ARGN})

    set_target_properties(${TARGET_NAME} PROPERTIES
        CXX_STANDARD 20
        CXX_STANDARD_REQUIRED ON
    )

    if(TOGGLE_PRE_COMPILED_HEADER)
        target_precompile_headers(${TARGET_NAME} PRIVATE ${CMAKE_SOURCE_DIR}/src/framework/pch.h)
    elseif(MSVC)
        target_compile_options(${TARGET_NAME} PRIVATE "/FI${CMAKE_SOURCE_DIR}/src/framework/pch.h")
    else()
        target_compile_options(${TARGET_NAME} PRIVATE "SHELL:-include ${CMAKE_SOURCE_DIR}/src/framework/pch.h")
    endif()

    target_link_libraries(${TARGET_NAME}
        PRIVATE
            otclient_core
            GTest::gtest
            GTest::gtest_main
    )

    if(ANDROID)
        target_link_libraries(${TARGET_NAME}
            PRIVATE
                log
                c
        )
    endif()

    target_compile_definitions(${TARGET_NAME}
        PRIVATE
            CLIENT
            FRAMEWORK_GRAPHICS
            FRAMEWORK_NET
            FRAMEWORK_SOUND
            FRAMEWORK_XML
    )

    if(MSVC)
        target_compile_options(${TARGET_NAME} PRIVATE /utf-8)
        if(BUILD_STATIC_LIBRARY)
            set_property(TARGET ${TARGET_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
        else()
            set_property(TARGET ${TARGET_NAME} PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
        endif()
    endif()

    # Discover at test time, not as a post-build step: the build then never has to run a test binary.
    # Run from the repository root: some tests read Lua modules through relative paths
    # (modules/...), which must not depend on where the build directory is.
    gtest_discover_tests(${TARGET_NAME}
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        DISCOVERY_MODE PRE_TEST
        DISCOVERY_TIMEOUT 60
        PROPERTIES TIMEOUT 60
    )
endfunction()

add_subdirectory(map)
add_subdirectory(stdext)
add_subdirectory(otml)
add_subdirectory(cyclopedia)

if(TOGGLE_RMLUI AND TOGGLE_FRAMEWORK_GRAPHICS AND NOT WASM)
    add_subdirectory(rml)
endif()
