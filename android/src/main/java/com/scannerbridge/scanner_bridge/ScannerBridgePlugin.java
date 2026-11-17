package com.scannerbridge.scanner_bridge;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;

import androidx.annotation.NonNull;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Android DataWedge bridge for scanner_bridge. */
public class ScannerBridgePlugin extends BroadcastReceiver implements
        FlutterPlugin,
        MethodChannel.MethodCallHandler,
        EventChannel.StreamHandler {

    private static final String METHOD_CHANNEL = "scanner_bridge/zebra_barcode";
    private static final String EVENT_CHANNEL = "scanner_bridge/zebra_barcode/events";
    private static final String DATAWEDGE_PACKAGE = "com.symbol.datawedge";
    private static final String SCAN_ACTION = "com.scannerbridge.scanner_bridge.SCAN";
    private static final String NOTIFICATION_ACTION = "com.symbol.datawedge.api.NOTIFICATION_ACTION";
    private static final String RESULT_ACTION = "com.symbol.datawedge.api.RESULT_ACTION";
    private static final String STATUS_NOTIFICATION = "SCANNER_STATUS";

    private Context applicationContext;
    private MethodChannel methodChannel;
    private EventChannel eventChannel;
    private EventChannel.EventSink eventSink;
    private boolean receiverRegistered;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        applicationContext = binding.getApplicationContext();
        methodChannel = new MethodChannel(binding.getBinaryMessenger(), METHOD_CHANNEL);
        eventChannel = new EventChannel(binding.getBinaryMessenger(), EVENT_CHANNEL);
        methodChannel.setMethodCallHandler(this);
        eventChannel.setStreamHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        stopDataWedge();
        if (methodChannel != null) {
            methodChannel.setMethodCallHandler(null);
        }
        if (eventChannel != null) {
            eventChannel.setStreamHandler(null);
        }
        methodChannel = null;
        eventChannel = null;
        applicationContext = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "isAvailable":
                result.success(isDataWedgeAvailable());
                break;
            case "start":
                if (!isDataWedgeAvailable()) {
                    result.error("zebra_unavailable", "Zebra DataWedge is not installed.", null);
                    return;
                }
                startDataWedge();
                result.success(null);
                break;
            case "stop":
                stopDataWedge();
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        eventSink = events;
    }

    @Override
    public void onCancel(Object arguments) {
        eventSink = null;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) {
            return;
        }

        if (SCAN_ACTION.equals(intent.getAction())) {
            final String value = intent.getStringExtra("com.symbol.datawedge.data_string");
            final String format = intent.getStringExtra("com.symbol.datawedge.label_type");
            if (value == null || value.isEmpty()) {
                return;
            }
            final Map<String, Object> event = new HashMap<>();
            event.put("event", "barcode");
            event.put("value", value);
            event.put("format", format);
            sendEvent(event);
            return;
        }

        if (intent.hasExtra(DataWedgeCommandBuilder.RESULT_GET_VERSION_INFO)) {
            final Bundle versionInfo = intent.getBundleExtra(
                    DataWedgeCommandBuilder.RESULT_GET_VERSION_INFO);
            if (versionInfo != null) {
                final Map<String, Object> event = new HashMap<>();
                event.put("event", "diagnostics");
                event.put("dataWedgeVersion", versionInfo.getString("DATAWEDGE"));
                event.put("profileName", applicationContext.getPackageName());
                event.put("applicationId", applicationContext.getPackageName());
                sendEvent(event);
            }
            return;
        }

        if (NOTIFICATION_ACTION.equals(intent.getAction()) &&
                intent.hasExtra("com.symbol.datawedge.api.NOTIFICATION")) {
            final Bundle notification = intent.getBundleExtra(
                    "com.symbol.datawedge.api.NOTIFICATION");
            if (notification == null ||
                    !STATUS_NOTIFICATION.equals(notification.getString("NOTIFICATION_TYPE"))) {
                return;
            }
            final Map<String, Object> event = new HashMap<>();
            event.put("event", "status");
            event.put("status", notification.getString("STATUS"));
            sendEvent(event);
            return;
        }

        if (RESULT_ACTION.equals(intent.getAction())) {
            final String result = intent.getStringExtra("RESULT");
            if (result == null || "SUCCESS".equalsIgnoreCase(result)) {
                return;
            }
            final Map<String, Object> event = new HashMap<>();
            event.put("event", "error");
            event.put("command", intent.getStringExtra("COMMAND"));
            event.put("result", result);
            event.put("commandIdentifier", intent.getStringExtra("COMMAND_IDENTIFIER"));
            final Bundle resultInfo = intent.getBundleExtra("RESULT_INFO");
            if (resultInfo != null) {
                event.put("resultInfo", bundleToStringMap(resultInfo));
            }
            sendEvent(event);
        }
    }

    private boolean isDataWedgeAvailable() {
        if (applicationContext == null) {
            return false;
        }
        try {
            applicationContext.getPackageManager().getPackageInfo(DATAWEDGE_PACKAGE, 0);
            return true;
        } catch (PackageManager.NameNotFoundException ignored) {
            return false;
        }
    }

    private void startDataWedge() {
        if (!receiverRegistered) {
            registerReceiver();
        }
        registerScannerStatusNotification();
        sendDataWedgeCommand(DataWedgeCommandBuilder.getVersionInfo());
        sendDataWedgeCommand(DataWedgeCommandBuilder.getScannerStatus());
        configureProfile();
        sendDataWedgeCommand(DataWedgeCommandBuilder.scannerInputPlugin("ENABLE_PLUGIN"));
    }

    private void stopDataWedge() {
        if (applicationContext == null || !receiverRegistered) {
            return;
        }
        sendDataWedgeCommand(DataWedgeCommandBuilder.scannerInputPlugin("DISABLE_PLUGIN"));
        sendDataWedgeCommand(
                DataWedgeCommandBuilder.unregisterScannerStatus(applicationContext.getPackageName()));

        applicationContext.unregisterReceiver(this);
        receiverRegistered = false;
    }

    private void registerReceiver() {
        final IntentFilter filter = new IntentFilter();
        filter.addAction(SCAN_ACTION);
        filter.addAction(NOTIFICATION_ACTION);
        filter.addAction(RESULT_ACTION);
        filter.addCategory(Intent.CATEGORY_DEFAULT);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            applicationContext.registerReceiver(this, filter, Context.RECEIVER_EXPORTED);
        } else {
            applicationContext.registerReceiver(this, filter);
        }
        receiverRegistered = true;
    }

    private void registerScannerStatusNotification() {
        sendDataWedgeCommand(
                DataWedgeCommandBuilder.registerScannerStatus(applicationContext.getPackageName()));
    }

    private void configureProfile() {
        final String applicationId = applicationContext.getPackageName();
        sendDataWedgeCommand(DataWedgeCommandBuilder.barcodeProfile(applicationId));
        sendDataWedgeCommand(DataWedgeCommandBuilder.intentProfile(applicationId, SCAN_ACTION));
    }

    @SuppressWarnings("unchecked")
    private void sendDataWedgeCommand(DataWedgeCommandBuilder.DataWedgeCommand command) {
        final Intent intent = new Intent(DataWedgeCommandBuilder.ACTION);
        final Object value = command.getValue();
        if (value instanceof Map) {
            intent.putExtra(command.getExtraKey(), bundleFromMap((Map<String, Object>) value));
        } else {
            intent.putExtra(command.getExtraKey(), String.valueOf(value));
        }
        intent.putExtra("SEND_RESULT", "true");
        intent.putExtra("COMMAND_IDENTIFIER", command.getCommandIdentifier());
        applicationContext.sendBroadcast(intent);
    }

    @SuppressWarnings("unchecked")
    private Bundle bundleFromMap(Map<String, Object> values) {
        final Bundle bundle = new Bundle();
        for (Map.Entry<String, Object> entry : values.entrySet()) {
            final Object value = entry.getValue();
            if (value instanceof Map) {
                bundle.putBundle(entry.getKey(), bundleFromMap((Map<String, Object>) value));
            } else if (value instanceof List) {
                final List<?> items = (List<?>) value;
                final Bundle[] bundles = new Bundle[items.size()];
                int index = 0;
                for (Object item : items) {
                    bundles[index++] = bundleFromMap((Map<String, Object>) item);
                }
                bundle.putParcelableArray(entry.getKey(), bundles);
            } else if (value instanceof String[]) {
                bundle.putStringArray(entry.getKey(), (String[]) value);
            } else if (value instanceof String) {
                bundle.putString(entry.getKey(), (String) value);
            }
        }
        return bundle;
    }

    private Map<String, String> bundleToStringMap(Bundle bundle) {
        final Map<String, String> values = new HashMap<>();
        for (String key : bundle.keySet()) {
            final Object value = bundle.get(key);
            values.put(key, String.valueOf(value));
        }
        return values;
    }

    private void sendEvent(Map<String, Object> event) {
        if (eventSink != null) {
            eventSink.success(event);
        }
    }
}
