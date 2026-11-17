package com.scannerbridge.scanner_bridge;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/** Builds the DataWedge commands used by scanner_bridge. */
final class DataWedgeCommandBuilder {
    static final String ACTION = "com.symbol.datawedge.api.ACTION";
    static final String SET_CONFIG = "com.symbol.datawedge.api.SET_CONFIG";
    static final String GET_SCANNER_STATUS = "com.symbol.datawedge.api.GET_SCANNER_STATUS";
    static final String GET_VERSION_INFO = "com.symbol.datawedge.api.GET_VERSION_INFO";
    static final String REGISTER_FOR_NOTIFICATION =
            "com.symbol.datawedge.api.REGISTER_FOR_NOTIFICATION";
    static final String UNREGISTER_FOR_NOTIFICATION =
            "com.symbol.datawedge.api.UNREGISTER_FOR_NOTIFICATION";
    static final String SCANNER_INPUT_PLUGIN =
            "com.symbol.datawedge.api.SCANNER_INPUT_PLUGIN";
    static final String RESULT_GET_VERSION_INFO =
            "com.symbol.datawedge.api.RESULT_GET_VERSION_INFO";

    private DataWedgeCommandBuilder() {}

    static DataWedgeCommand getScannerStatus() {
        return new DataWedgeCommand(GET_SCANNER_STATUS, "", "scanner_bridge_status");
    }

    static DataWedgeCommand getVersionInfo() {
        return new DataWedgeCommand(GET_VERSION_INFO, "", "scanner_bridge_version");
    }

    static DataWedgeCommand registerScannerStatus(String applicationId) {
        return new DataWedgeCommand(
                REGISTER_FOR_NOTIFICATION,
                notificationBundle(applicationId),
                "scanner_bridge_register_status");
    }

    static DataWedgeCommand unregisterScannerStatus(String applicationId) {
        return new DataWedgeCommand(
                UNREGISTER_FOR_NOTIFICATION,
                notificationBundle(applicationId),
                "scanner_bridge_unregister_status");
    }

    static DataWedgeCommand barcodeProfile(String applicationId) {
        final Map<String, Object> app = map(
                "PACKAGE_NAME", applicationId,
                "ACTIVITY_LIST", new String[]{"*"});
        final Map<String, Object> barcodeParams = map(
                "scanner_input_enabled", "true");
        final Map<String, Object> barcodePlugin = map(
                "PLUGIN_NAME", "BARCODE",
                "RESET_CONFIG", "true",
                "PARAM_LIST", barcodeParams);
        final Map<String, Object> profile = map(
                "PROFILE_NAME", applicationId,
                "PROFILE_ENABLED", "true",
                "CONFIG_MODE", "CREATE_IF_NOT_EXIST",
                "APP_LIST", Collections.singletonList(app),
                "PLUGIN_CONFIG", barcodePlugin);
        return new DataWedgeCommand(SET_CONFIG, profile, "scanner_bridge_barcode_profile");
    }

    static DataWedgeCommand intentProfile(String applicationId, String scanAction) {
        final Map<String, Object> intentParams = map(
                "intent_output_enabled", "true",
                "intent_action", scanAction,
                "intent_delivery", "2");
        final Map<String, Object> intentPlugin = map(
                "PLUGIN_NAME", "INTENT",
                "RESET_CONFIG", "true",
                "PARAM_LIST", intentParams);
        final Map<String, Object> profile = map(
                "PROFILE_NAME", applicationId,
                "PROFILE_ENABLED", "true",
                "CONFIG_MODE", "UPDATE",
                "PLUGIN_CONFIG", intentPlugin);
        return new DataWedgeCommand(SET_CONFIG, profile, "scanner_bridge_intent_profile");
    }

    static DataWedgeCommand scannerInputPlugin(String parameter) {
        return new DataWedgeCommand(
                SCANNER_INPUT_PLUGIN,
                parameter,
                "scanner_bridge_input_" + parameter);
    }

    private static Map<String, Object> notificationBundle(String applicationId) {
        return map(
                "com.symbol.datawedge.api.APPLICATION_NAME", applicationId,
                "com.symbol.datawedge.api.NOTIFICATION_TYPE", "SCANNER_STATUS");
    }

    private static Map<String, Object> map(Object... values) {
        final Map<String, Object> result = new LinkedHashMap<>();
        for (int index = 0; index < values.length; index += 2) {
            result.put((String) values[index], values[index + 1]);
        }
        return result;
    }

    static final class DataWedgeCommand {
        private final String extraKey;
        private final Object value;
        private final String commandIdentifier;

        DataWedgeCommand(String extraKey, Object value, String commandIdentifier) {
            this.extraKey = extraKey;
            this.value = value;
            this.commandIdentifier = commandIdentifier;
        }

        String getExtraKey() {
            return extraKey;
        }

        Object getValue() {
            return value;
        }

        String getCommandIdentifier() {
            return commandIdentifier;
        }
    }
}
