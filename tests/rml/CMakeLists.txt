# Imported targets are scoped to the directory that found them, so look RmlUi up again here.
find_package(RmlUi CONFIG REQUIRED)

otclient_add_gtest(rml_tests
    rmlbackend_test.cpp
    rmlmanager_image_test.cpp
    rmlmanager_text_test.cpp
    rmlrenderer_test.cpp
)

target_compile_definitions(rml_tests PRIVATE FRAMEWORK_RMLUI)
target_link_libraries(rml_tests PRIVATE RmlUi::RmlUi)
