set(PROTOCOL_TEST_SOURCES
    ${CMAKE_CURRENT_SOURCE_DIR}/fight_modes_test.cpp
)

otclient_add_gtest(otclient_protocol_tests ${PROTOCOL_TEST_SOURCES})
