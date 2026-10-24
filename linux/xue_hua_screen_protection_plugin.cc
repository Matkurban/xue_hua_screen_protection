#include "include/xue_hua_screen_protection/xue_hua_screen_protection_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <ctime>

#include "xue_hua_screen_protection_plugin_private.h"

#define XUE_HUA_SCREEN_PROTECTION_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), xue_hua_screen_protection_plugin_get_type(), \
                              XueHuaScreenProtectionPlugin))

struct _XueHuaScreenProtectionPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  FlMethodChannel* method_channel;
  FlEventChannel* event_channel;
  gboolean event_channel_listening;

  gboolean is_secure_screen_enabled;
  gboolean is_mask_currently_visible;
  gboolean mask_enabled;
  gchar* mask_style;
  gboolean protect_on_window_blur;

  GtkWindow* tracked_window;
  gulong focus_out_handler_id;
  gulong focus_in_handler_id;
};

G_DEFINE_TYPE(XueHuaScreenProtectionPlugin,
              xue_hua_screen_protection_plugin,
              g_object_get_type())

static gint64 current_epoch_millis() {
  return g_get_real_time() / 1000;
}

static void emit_protection_event(XueHuaScreenProtectionPlugin* self,
                                  const gchar* type,
                                  const gchar* reason) {
  g_autoptr(FlValue) payload = fl_value_new_map();
  fl_value_set_string_take(payload, "type", fl_value_new_string(type));
  fl_value_set_string_take(payload, "timestamp",
                           fl_value_new_int(current_epoch_millis()));
  fl_value_set_string_take(payload, "platform", fl_value_new_string("linux"));
  fl_value_set_string_take(payload, "isCaptured", fl_value_new_bool(FALSE));

  g_autoptr(FlValue) metadata = fl_value_new_map();
  if (reason != nullptr) {
    fl_value_set_string_take(metadata, "reason", fl_value_new_string(reason));
  }
  fl_value_set_string_take(payload, "metadata", g_steal_pointer(&metadata));

  if (self->event_channel != nullptr && self->event_channel_listening) {
    fl_event_channel_send(self->event_channel, payload, nullptr, nullptr);
  }
  if (self->method_channel != nullptr) {
    fl_method_channel_invoke_method(self->method_channel, "onProtectionEvent",
                                    payload, nullptr, nullptr, nullptr);
  }
}

static void set_mask_visible(XueHuaScreenProtectionPlugin* self,
                             gboolean visible,
                             const gchar* reason) {
  if (self->is_mask_currently_visible == visible) {
    return;
  }
  self->is_mask_currently_visible = visible;
  emit_protection_event(self, visible ? "maskShown" : "maskHidden", reason);
}

static gboolean on_window_focus_out(GtkWidget* widget,
                                    GdkEventFocus* event,
                                    gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  if (self->mask_enabled && g_strcmp0(self->mask_style, "none") != 0 &&
      self->protect_on_window_blur) {
    set_mask_visible(self, TRUE, "gtk_focus_out");
  }
  return FALSE;
}

static gboolean on_window_focus_in(GtkWidget* widget,
                                   GdkEventFocus* event,
                                   gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  if (self->is_mask_currently_visible) {
    set_mask_visible(self, FALSE, "gtk_focus_in");
  }
  return FALSE;
}

static void ensure_window_signals_connected(XueHuaScreenProtectionPlugin* self) {
  if (self->tracked_window != nullptr || self->registrar == nullptr) {
    return;
  }
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) return;
  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (!GTK_IS_WINDOW(toplevel)) return;

  self->tracked_window = GTK_WINDOW(toplevel);
  gtk_widget_add_events(toplevel, GDK_FOCUS_CHANGE_MASK);
  self->focus_out_handler_id = g_signal_connect(
      toplevel, "focus-out-event", G_CALLBACK(on_window_focus_out), self);
  self->focus_in_handler_id = g_signal_connect(
      toplevel, "focus-in-event", G_CALLBACK(on_window_focus_in), self);
}

FlMethodResponse* get_linux_capabilities_response() {
  struct utsname uname_data = {};
  uname(&uname_data);
  g_autofree gchar* os_ver =
      g_strdup_printf("Linux %s (%s)", uname_data.release, uname_data.machine);

  g_autoptr(FlValue) limitations = fl_value_new_list();
  fl_value_append_take(
      limitations,
      fl_value_new_string(
          "Linux X11 and Wayland desktop compositors do not expose an application-level API to block OS screenshots or screen recording."));
  fl_value_append_take(
      limitations,
      fl_value_new_string(
          "Focus-out privacy masking and ScreenProtectionWatermark are supported on Linux."));

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "platform", fl_value_new_string("linux"));
  fl_value_set_string_take(map, "osVersion", fl_value_new_string(os_ver));
  fl_value_set_string_take(map, "supportsHardwareAntiScreenshot",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "supportsHardwareAntiRecording",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "supportsScreenshotDetection",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "supportsRecordingDetection",
                           fl_value_new_bool(FALSE));
  fl_value_set_string_take(map, "supportsNativeAppSwitcherMask",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(map, "supportsNativeBlurEffect",
                           fl_value_new_bool(TRUE));
  fl_value_set_string_take(map, "limitations", g_steal_pointer(&limitations));

  return FL_METHOD_RESPONSE(fl_method_success_response_new(map));
}

static void xue_hua_screen_protection_plugin_handle_method_call(
    XueHuaScreenProtectionPlugin* self,
    FlMethodCall* method_call) {
  ensure_window_signals_connected(self);

  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  if (strcmp(method, "setSecureScreen") == 0) {
    gboolean enabled = FALSE;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* val = fl_value_lookup_string(args, "enabled");
      if (val != nullptr && fl_value_get_type(val) == FL_VALUE_TYPE_BOOL) {
        enabled = fl_value_get_bool(val);
      }
    }
    self->is_secure_screen_enabled = enabled;
    g_autoptr(FlValue) res = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "isSecureScreenEnabled") == 0) {
    g_autoptr(FlValue) res = fl_value_new_bool(self->is_secure_screen_enabled);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "configureAppSwitcherProtection") == 0) {
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* en = fl_value_lookup_string(args, "enabled");
      if (en != nullptr && fl_value_get_type(en) == FL_VALUE_TYPE_BOOL) {
        self->mask_enabled = fl_value_get_bool(en);
      }
      FlValue* st = fl_value_lookup_string(args, "style");
      if (st != nullptr && fl_value_get_type(st) == FL_VALUE_TYPE_STRING) {
        g_free(self->mask_style);
        self->mask_style = g_strdup(fl_value_get_string(st));
      }
      FlValue* blur_focus =
          fl_value_lookup_string(args, "protectOnWindowBlur");
      if (blur_focus != nullptr &&
          fl_value_get_type(blur_focus) == FL_VALUE_TYPE_BOOL) {
        self->protect_on_window_blur = fl_value_get_bool(blur_focus);
      }
    }
    if (!self->mask_enabled || g_strcmp0(self->mask_style, "none") == 0) {
      set_mask_visible(self, FALSE, "config_disabled");
    }
    g_autoptr(FlValue) res = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "configureWebProtection") == 0) {
    g_autoptr(FlValue) res = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "isScreenBeingRecorded") == 0) {
    g_autoptr(FlValue) res = fl_value_new_bool(FALSE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "getProtectionStatus") == 0) {
    g_autoptr(FlValue) status = fl_value_new_map();
    fl_value_set_string_take(status, "isSecureScreenEnabled",
                             fl_value_new_bool(self->is_secure_screen_enabled));
    fl_value_set_string_take(
        status, "isAppSwitcherMaskEnabled",
        fl_value_new_bool(self->mask_enabled &&
                          g_strcmp0(self->mask_style, "none") != 0));
    fl_value_set_string_take(status, "isScreenBeingRecorded",
                             fl_value_new_bool(FALSE));
    fl_value_set_string_take(
        status, "isMaskCurrentlyVisible",
        fl_value_new_bool(self->is_mask_currently_visible));
    fl_value_set_string_take(status, "platform", fl_value_new_string("linux"));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(status));
  } else if (strcmp(method, "getCapabilities") == 0) {
    response = get_linux_capabilities_response();
  } else if (strcmp(method, "showPrivacyMask") == 0) {
    set_mask_visible(self, TRUE, "manual");
    g_autoptr(FlValue) res = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else if (strcmp(method, "hidePrivacyMask") == 0) {
    set_mask_visible(self, FALSE, "manual");
    g_autoptr(FlValue) res = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(res));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  fl_method_call_respond(method_call, response, nullptr);
}

static FlMethodErrorResponse* event_channel_listen_cb(FlEventChannel* channel,
                                                      FlValue* args,
                                                      gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  self->event_channel_listening = TRUE;
  return nullptr;
}

static FlMethodErrorResponse* event_channel_cancel_cb(FlEventChannel* channel,
                                                      FlValue* args,
                                                      gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  self->event_channel_listening = FALSE;
  return nullptr;
}

static void xue_hua_screen_protection_plugin_dispose(GObject* object) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(object);
  if (self->tracked_window != nullptr) {
    if (self->focus_out_handler_id > 0) {
      g_signal_handler_disconnect(self->tracked_window,
                                  self->focus_out_handler_id);
      self->focus_out_handler_id = 0;
    }
    if (self->focus_in_handler_id > 0) {
      g_signal_handler_disconnect(self->tracked_window,
                                  self->focus_in_handler_id);
      self->focus_in_handler_id = 0;
    }
    self->tracked_window = nullptr;
  }
  g_clear_object(&self->method_channel);
  g_clear_object(&self->event_channel);
  g_clear_object(&self->registrar);
  g_free(self->mask_style);
  self->mask_style = nullptr;
  G_OBJECT_CLASS(xue_hua_screen_protection_plugin_parent_class)
      ->dispose(object);
}

static void xue_hua_screen_protection_plugin_class_init(
    XueHuaScreenProtectionPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = xue_hua_screen_protection_plugin_dispose;
}

static void xue_hua_screen_protection_plugin_init(
    XueHuaScreenProtectionPlugin* self) {
  self->is_secure_screen_enabled = FALSE;
  self->is_mask_currently_visible = FALSE;
  self->mask_enabled = FALSE;
  self->mask_style = g_strdup("blur");
  self->protect_on_window_blur = TRUE;
  self->event_channel_listening = FALSE;
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  XueHuaScreenProtectionPlugin* plugin =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  xue_hua_screen_protection_plugin_handle_method_call(plugin, method_call);
}

void xue_hua_screen_protection_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  XueHuaScreenProtectionPlugin* plugin = XUE_HUA_SCREEN_PROTECTION_PLUGIN(
      g_object_new(xue_hua_screen_protection_plugin_get_type(), nullptr));

  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->method_channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "com.kurban.xue_hua_screen_protection/methods",
                            FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->method_channel, method_call_cb, g_object_ref(plugin),
      g_object_unref);

  plugin->event_channel =
      fl_event_channel_new(fl_plugin_registrar_get_messenger(registrar),
                           "com.kurban.xue_hua_screen_protection/events",
                           FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(
      plugin->event_channel, event_channel_listen_cb, event_channel_cancel_cb,
      g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
