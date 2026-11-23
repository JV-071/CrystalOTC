# RmlUi for CrystalOTC. Differs from the stock vcpkg port on purpose:
#  - version 6.3 (the baseline pinned in vcpkg.json ships 6.2);
#  - the Lua plugin is always built, against LuaJIT (the client's Lua), not PUC Lua;
#  - RmlUi keeps its bundled containers and installs its own FindLuaJIT.cmake, so the
#    stock port's two patches are not needed;
#  - the headers are left untouched: static consumers define RMLUI_STATIC_LIB
#    (the exported CMake target does it; vc18/settings.props does it for MSBuild);
#  - lua-datamodel-lifetime.patch fixes the Lua plugin's data models for a client that closes
#    them (Context:CloseDataModel), which this one does whenever an RmlUi window is destroyed:
#      * a table proxy (a nested table of a model) keeps its model's userdata alive. Its
#        finalizer used to read that userdata after the collector had freed it: random crashes
#        and heap corruption a few incremental collections after a model was closed;
#      * using a table proxy of a closed model raises "DataModel closed" instead of indexing nil;
#      * open models are indexed per context instead of by name alone, so closing a model in one
#        window no longer tears down the model of the same name that another window has open.
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO mikke89/RmlUi
    REF 6.3
    SHA512 b66d2a3621ca2690d6e826661203fc3a4babe16243ed01b2f884d149f5b7ee598241f1f743262c7a8fbf8ae98641d5c5526fc63d8a6283638b6dc021d23e103e
    HEAD_REF master
    PATCHES
        lua-datamodel-lifetime.patch
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DRMLUI_FONT_ENGINE=freetype
        -DRMLUI_LUA_BINDINGS=ON
        -DRMLUI_LUA_BINDINGS_LIBRARY=luajit
        -DRMLUI_SAMPLES=OFF
        -DBUILD_TESTING=OFF
        -DRMLUI_COMPILER_OPTIONS=OFF
)

vcpkg_cmake_install()
vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/RmlUi)
vcpkg_copy_pdbs()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

configure_file("${CMAKE_CURRENT_LIST_DIR}/usage" "${CURRENT_PACKAGES_DIR}/share/${PORT}/usage" COPYONLY)
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt" "${SOURCE_PATH}/Source/Debugger/LICENSE.txt")
