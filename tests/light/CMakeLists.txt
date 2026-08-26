set(LIGHT_TEST_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/cloud_field_test.cpp
)

otclient_add_gtest(otclient_light_tests ${LIGHT_TEST_SOURCES})
