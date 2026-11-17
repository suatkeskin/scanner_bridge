package com.scannerbridge.scanner_bridge;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;

import java.util.List;
import java.util.Map;

import org.junit.Test;

public class DataWedgeCommandBuilderTest {
    @Test
    public void barcodeProfileUsesApplicationIdAndEnablesScannerInput() {
        final String applicationId = "com.example.scanner";
        final DataWedgeCommandBuilder.DataWedgeCommand command =
                DataWedgeCommandBuilder.barcodeProfile(applicationId);

        assertEquals(DataWedgeCommandBuilder.SET_CONFIG, command.getExtraKey());
        assertEquals("scanner_bridge_barcode_profile", command.getCommandIdentifier());

        final Map<String, Object> profile = map(command.getValue());
        assertEquals(applicationId, profile.get("PROFILE_NAME"));
        assertEquals("CREATE_IF_NOT_EXIST", profile.get("CONFIG_MODE"));

        final List<?> appList = (List<?>) profile.get("APP_LIST");
        final Map<String, Object> app = map(appList.get(0));
        assertEquals(applicationId, app.get("PACKAGE_NAME"));
        assertArrayEquals(new String[]{"*"}, (String[]) app.get("ACTIVITY_LIST"));

        final Map<String, Object> plugin = map(profile.get("PLUGIN_CONFIG"));
        assertEquals("BARCODE", plugin.get("PLUGIN_NAME"));
        final Map<String, Object> params = map(plugin.get("PARAM_LIST"));
        assertEquals("true", params.get("scanner_input_enabled"));
    }

    @Test
    public void intentProfileUsesBroadcastOutput() {
        final DataWedgeCommandBuilder.DataWedgeCommand command =
                DataWedgeCommandBuilder.intentProfile(
                        "com.example.scanner",
                        "com.example.scanner.SCAN");

        final Map<String, Object> profile = map(command.getValue());
        assertEquals("UPDATE", profile.get("CONFIG_MODE"));
        final Map<String, Object> plugin = map(profile.get("PLUGIN_CONFIG"));
        final Map<String, Object> params = map(plugin.get("PARAM_LIST"));
        assertEquals("true", params.get("intent_output_enabled"));
        assertEquals("com.example.scanner.SCAN", params.get("intent_action"));
        assertEquals("2", params.get("intent_delivery"));
    }

    @Test
    public void lifecycleCommandsHaveStableKeysAndIdentifiers() {
        final DataWedgeCommandBuilder.DataWedgeCommand enable =
                DataWedgeCommandBuilder.scannerInputPlugin("ENABLE_PLUGIN");
        final DataWedgeCommandBuilder.DataWedgeCommand disable =
                DataWedgeCommandBuilder.scannerInputPlugin("DISABLE_PLUGIN");
        final DataWedgeCommandBuilder.DataWedgeCommand register =
                DataWedgeCommandBuilder.registerScannerStatus("com.example.scanner");

        assertEquals(DataWedgeCommandBuilder.SCANNER_INPUT_PLUGIN, enable.getExtraKey());
        assertEquals("ENABLE_PLUGIN", enable.getValue());
        assertEquals("DISABLE_PLUGIN", disable.getValue());
        assertEquals("scanner_bridge_input_ENABLE_PLUGIN", enable.getCommandIdentifier());
        assertEquals(DataWedgeCommandBuilder.REGISTER_FOR_NOTIFICATION, register.getExtraKey());
        assertNotNull(register.getValue());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Object value) {
        return (Map<String, Object>) value;
    }
}
