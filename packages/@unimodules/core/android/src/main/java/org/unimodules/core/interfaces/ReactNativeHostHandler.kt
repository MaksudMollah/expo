package org.unimodules.core.interfaces

import com.facebook.react.bridge.JavaScriptContextHolder
import com.facebook.react.bridge.ReactApplicationContext

interface ReactNativeHostHandler {
  /**
   * Given chance for modules to override react bundle file.
   * e.g. for expo-updates
   *
   * @return custom path to bundle file, or null if not to override
   */
  fun getJSBundleFile(): String? {
    return null
  }

  /**
   * Given chance for modules to override react bundle asset name.
   * e.g. for expo-updates
   *
   * @return custom bundle asset name, or null if not to override
   */
  fun getBundleAssetName(): String? {
    return null
  }

  /**
   * Given chance for JSI modules to register, e.g. for react-native-reanimated
   *
   * @param reactApplicationContext React Native app context
   * @param jsContext JavaScript context
   */
  fun onRegisterJSIModules(reactApplicationContext: ReactApplicationContext,
                           jsContext: JavaScriptContextHolder) {
  }

  /**
   * Event callback before createReactInstanceManager
   *
   * @param useDeveloperSupport true if using developer support tools,
   *                            typically equals to BuildConfig.DEBUG
   */
  fun onWillCreateReactInstanceManager(useDeveloperSupport: Boolean) {
  }
}
