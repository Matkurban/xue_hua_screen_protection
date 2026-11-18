#include "include/xue_hua_screen_protection/xue_hua_screen_protection_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <sys/utsname.h>

#include <cstring>
#include <ctime>

#include "messages.g.h"
#include "xue_hua_screen_protection_plugin_private.h"

#define XUE_HUA_SCREEN_PROTECTION_PLUGIN(obj)                                     \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), xue_hua_screen_protection_plugin_get_type(), \
                              XueHuaScreenProtectionPlugin))

struct _XueHuaScreenProtectionPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  XueHuaScreenProtectionScreenProtectionFlutterApi* flutter_api;

  gboolean is_secure_screen_enabled;
  gboolean is_mask_currently_visible;
  gboolean mask_enabled;
  gboolean mask_enabled_by_secure;
  XueHuaScreenProtectionScreenProtectionMaskStyleMessage mask_style;
  gdouble mask_blur_sigma;
  guint32 mask_background_color;
  guint32 mask_text_color;
  gchar* mask_title;
  gchar* mask_subtitle;
  gboolean mask_show_lock_icon;
  gboolean protect_on_window_blur;

  GtkWindow* tracked_window;
  GtkWidget* mask_overlay;
  GtkWidget* mask_title_label;
  GtkWidget* mask_subtitle_label;
  gulong focus_out_handler_id;
  gulong focus_in_handler_id;
  gulong size_allocate_handler_id;
  guint focus_out_timeout_id;
  GtkCssProvider* mask_css_provider;
};

G_DEFINE_TYPE(XueHuaScreenProtectionPlugin,
              xue_hua_screen_protection_plugin,
              g_object_get_type())

static void ensure_window_signals_connected(XueHuaScreenProtectionPlugin* self);
static void ensure_mask_overlay_created(XueHuaScreenProtectionPlugin* self);
static void sync_mask_overlay_geometry(XueHuaScreenProtectionPlugin* self);
static void apply_mask_styles(XueHuaScreenProtectionPlugin* self);
static void set_mask_visible(XueHuaScreenProtectionPlugin* self,
                             gboolean visible,
                             const gchar* reason);

static gint64 current_epoch_millis() {
  return g_get_real_time() / 1000;
}

static void emit_protection_event(
    XueHuaScreenProtectionPlugin* self,
    XueHuaScreenProtectionScreenProtectionEventTypeMessage type,
    const gchar* reason) {
  if (self->flutter_api == nullptr) {
    return;
  }

  g_autoptr(FlValue) metadata = fl_value_new_map();
  if (reason != nullptr) {
    fl_value_set_string_take(metadata, "reason", fl_value_new_string(reason));
  }

  g_autoptr(XueHuaScreenProtectionScreenProtectionEventMessage) event =
      xue_hua_screen_protection_screen_protection_event_message_new(
          type, current_epoch_millis(), "linux", FALSE, metadata);

  xue_hua_screen_protection_screen_protection_flutter_api_on_protection_event(
      self->flutter_api, event, nullptr, nullptr, nullptr);
}

static void argb_to_rgba_string(guint32 argb, gchar* out, gsize out_len) {
  const guint8 a = static_cast<guint8>((argb >> 24) & 0xFF);
  const guint8 r = static_cast<guint8>((argb >> 16) & 0xFF);
  const guint8 g = static_cast<guint8>((argb >> 8) & 0xFF);
  const guint8 b = static_cast<guint8>(argb & 0xFF);
  g_snprintf(out, out_len, "rgba(%u,%u,%u,%.3f)", r, g, b, a / 255.0);
}

static void apply_mask_styles(XueHuaScreenProtectionPlugin* self) {
  if (self->mask_overlay == nullptr) {
    return;
  }

  gchar bg[64];
  gchar fg[64];
  argb_to_rgba_string(self->mask_background_color, bg, sizeof(bg));
  argb_to_rgba_string(self->mask_text_color, fg, sizeof(fg));

  // Approximate "blur" with a denser translucent panel when style is blur;
  // GTK3 cannot easily frosted-blur arbitrary window contents.
  g_autofree gchar* css = g_strdup_printf(
      ".xue-hua-privacy-mask {"
      "  background-color: %s;"
      "}"
      ".xue-hua-privacy-mask-title {"
      "  color: %s;"
      "  font-size: 22px;"
      "  font-weight: bold;"
      "}"
      ".xue-hua-privacy-mask-subtitle {"
      "  color: %s;"
      "  font-size: 14px;"
      "  opacity: 0.85;"
      "}",
      bg, fg, fg);

  if (self->mask_css_provider == nullptr) {
    self->mask_css_provider = gtk_css_provider_new();
  }
  gtk_css_provider_load_from_data(self->mask_css_provider, css, -1, nullptr);
  GtkStyleContext* ctx = gtk_widget_get_style_context(self->mask_overlay);
  gtk_style_context_add_provider(ctx, GTK_STYLE_PROVIDER(self->mask_css_provider),
                                 GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);

  if (self->mask_title_label != nullptr) {
    g_autofree gchar* title = nullptr;
    if (self->mask_show_lock_icon) {
      title = g_strdup_printf("🔒 %s",
                              self->mask_title != nullptr ? self->mask_title
                                                          : "Privacy Protected");
    } else {
      title = g_strdup(self->mask_title != nullptr ? self->mask_title
                                                   : "Privacy Protected");
    }
    gtk_label_set_text(GTK_LABEL(self->mask_title_label), title);
  }
  if (self->mask_subtitle_label != nullptr) {
    gtk_label_set_text(
        GTK_LABEL(self->mask_subtitle_label),
        self->mask_subtitle != nullptr ? self->mask_subtitle : "");
  }
}

static void sync_mask_overlay_geometry(XueHuaScreenProtectionPlugin* self) {
  if (self->mask_overlay == nullptr || self->tracked_window == nullptr) {
    return;
  }
  gint root_x = 0;
  gint root_y = 0;
  gint width = 0;
  gint height = 0;
  gtk_window_get_position(self->tracked_window, &root_x, &root_y);
  gtk_window_get_size(self->tracked_window, &width, &height);
  if (width <= 0 || height <= 0) {
    return;
  }
  gtk_window_move(GTK_WINDOW(self->mask_overlay), root_x, root_y);
  gtk_window_resize(GTK_WINDOW(self->mask_overlay), width, height);
}

static gboolean on_tracked_configure(GtkWidget* /*widget*/,
                                     GdkEventConfigure* /*event*/,
                                     gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  if (self->is_mask_currently_visible) {
    sync_mask_overlay_geometry(self);
  }
  return FALSE;
}

static gboolean on_overlay_button_press(GtkWidget* /*widget*/,
                                        GdkEventButton* /*event*/,
                                        gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  set_mask_visible(self, FALSE, "overlay_click");
  if (self->tracked_window != nullptr) {
    gtk_window_present(self->tracked_window);
  }
  return TRUE;
}

static void ensure_mask_overlay_created(XueHuaScreenProtectionPlugin* self) {
  if (self->mask_overlay != nullptr || self->tracked_window == nullptr) {
    return;
  }

  GtkWidget* window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
  gtk_window_set_resizable(GTK_WINDOW(window), FALSE);
  gtk_window_set_skip_taskbar_hint(GTK_WINDOW(window), TRUE);
  gtk_window_set_skip_pager_hint(GTK_WINDOW(window), TRUE);
  gtk_window_set_accept_focus(GTK_WINDOW(window), FALSE);
  gtk_window_set_focus_on_map(GTK_WINDOW(window), FALSE);
  gtk_window_set_keep_above(GTK_WINDOW(window), FALSE);
  gtk_window_set_transient_for(GTK_WINDOW(window), self->tracked_window);
  gtk_window_set_type_hint(GTK_WINDOW(window), GDK_WINDOW_TYPE_HINT_UTILITY);
  gtk_widget_set_app_paintable(window, TRUE);
  gtk_widget_set_name(window, "xue_hua_privacy_mask");
  gtk_style_context_add_class(gtk_widget_get_style_context(window),
                              "xue-hua-privacy-mask");

  GtkWidget* center = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12);
  gtk_widget_set_halign(center, GTK_ALIGN_CENTER);
  gtk_widget_set_valign(center, GTK_ALIGN_CENTER);
  gtk_widget_set_margin_start(center, 24);
  gtk_widget_set_margin_end(center, 24);

  self->mask_title_label = gtk_label_new("Privacy Protected");
  gtk_style_context_add_class(
      gtk_widget_get_style_context(self->mask_title_label),
      "xue-hua-privacy-mask-title");
  gtk_label_set_justify(GTK_LABEL(self->mask_title_label), GTK_JUSTIFY_CENTER);
  gtk_label_set_line_wrap(GTK_LABEL(self->mask_title_label), TRUE);

  self->mask_subtitle_label = gtk_label_new("");
  gtk_style_context_add_class(
      gtk_widget_get_style_context(self->mask_subtitle_label),
      "xue-hua-privacy-mask-subtitle");
  gtk_label_set_justify(GTK_LABEL(self->mask_subtitle_label),
                        GTK_JUSTIFY_CENTER);
  gtk_label_set_line_wrap(GTK_LABEL(self->mask_subtitle_label), TRUE);

  gtk_box_pack_start(GTK_BOX(center), self->mask_title_label, FALSE, FALSE, 0);
  gtk_box_pack_start(GTK_BOX(center), self->mask_subtitle_label, FALSE, FALSE,
                     0);
  gtk_container_add(GTK_CONTAINER(window), center);

  // Keep the overlay aligned when the host window moves/resizes.
  self->size_allocate_handler_id = g_signal_connect(
      self->tracked_window, "configure-event",
      G_CALLBACK(on_tracked_configure), self);

  gtk_widget_add_events(window, GDK_BUTTON_PRESS_MASK);
  g_signal_connect(window, "button-press-event",
                   G_CALLBACK(on_overlay_button_press), self);

  self->mask_overlay = window;
  apply_mask_styles(self);
}

static void set_mask_visible(XueHuaScreenProtectionPlugin* self,
                             gboolean visible,
                             const gchar* reason) {
  if (self->is_mask_currently_visible == visible) {
    return;
  }

  ensure_window_signals_connected(self);
  ensure_mask_overlay_created(self);

  self->is_mask_currently_visible = visible;
  if (visible) {
    ensure_mask_overlay_created(self);
    if (self->mask_overlay != nullptr) {
      apply_mask_styles(self);
      sync_mask_overlay_geometry(self);
      gtk_window_set_keep_above(GTK_WINDOW(self->mask_overlay), TRUE);
      // Restore full input shape when shown.
      GdkWindow* gdk_win = gtk_widget_get_window(self->mask_overlay);
      if (gdk_win != nullptr) {
        gdk_window_input_shape_combine_region(gdk_win, nullptr, 0, 0);
      }
      gtk_widget_show_all(self->mask_overlay);
    }
  } else if (self->mask_overlay != nullptr) {
    // Hide + drop keep-above + clear input shape. Avoid destroy(): tearing down
    // a transient GTK window can leave the Flutter view unable to accept driver
    // taps on some compositors.
    gtk_window_set_keep_above(GTK_WINDOW(self->mask_overlay), FALSE);
    gtk_widget_hide(self->mask_overlay);
    GdkWindow* gdk_win = gtk_widget_get_window(self->mask_overlay);
    if (gdk_win != nullptr) {
      cairo_region_t* empty = cairo_region_create();
      gdk_window_input_shape_combine_region(gdk_win, empty, 0, 0);
      cairo_region_destroy(empty);
    }
    if (self->tracked_window != nullptr) {
      gtk_window_present(self->tracked_window);
    }
  }

  emit_protection_event(
      self,
      visible
          ? XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_EVENT_TYPE_MESSAGE_MASK_SHOWN
          : XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_EVENT_TYPE_MESSAGE_MASK_HIDDEN,
      reason);
}

static gboolean delayed_focus_out_mask(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  self->focus_out_timeout_id = 0;
  if (self->mask_enabled &&
      self->mask_style !=
          XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_NONE &&
      self->protect_on_window_blur) {
    set_mask_visible(self, TRUE, "gtk_focus_out");
  }
  return G_SOURCE_REMOVE;
}

static gboolean on_window_focus_out(GtkWidget* /*widget*/,
                                    GdkEventFocus* /*event*/,
                                    gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  if (self->mask_enabled &&
      self->mask_style !=
          XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_NONE &&
      self->protect_on_window_blur) {
    // Debounce: brief focus flicker during route pushes / dialogs should not
    // permanently cover the Flutter view (breaks Flutter Driver taps).
    if (self->focus_out_timeout_id == 0) {
      self->focus_out_timeout_id =
          g_timeout_add(300, delayed_focus_out_mask, self);
    }
  }
  return FALSE;
}

static gboolean on_window_focus_in(GtkWidget* /*widget*/,
                                   GdkEventFocus* /*event*/,
                                   gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  if (self->focus_out_timeout_id != 0) {
    g_source_remove(self->focus_out_timeout_id);
    self->focus_out_timeout_id = 0;
  }
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

XueHuaScreenProtectionScreenProtectionCapabilitiesMessage*
get_linux_capabilities_message() {
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
          "Focus-out privacy masking and ScreenProtectionWatermark are supported on Linux. Blur style uses a translucent overlay (true backdrop blur is compositor-dependent)."));

  return xue_hua_screen_protection_screen_protection_capabilities_message_new(
      "linux", os_ver, FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, limitations);
}

// -----------------------------------------------------------------------------
// Pigeon ScreenProtectionHostApi VTable Handlers
// -----------------------------------------------------------------------------

static XueHuaScreenProtectionScreenProtectionHostApiSetSecureScreenResponse*
handle_set_secure_screen(gboolean enabled, gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);

  self->is_secure_screen_enabled = enabled;
  // Linux has no FLAG_SECURE equivalent; enabling secure screen activates
  // focus-out privacy masking as the documented fallback defense.
  if (enabled) {
    if (!self->mask_enabled ||
        self->mask_style ==
            XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_NONE) {
      self->mask_enabled_by_secure = TRUE;
    }
    self->mask_enabled = TRUE;
    self->protect_on_window_blur = TRUE;
    if (self->mask_style ==
        XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_NONE) {
      self->mask_style =
          XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_BLUR;
    }
  } else if (self->mask_enabled_by_secure) {
    // Undo only the auto-armed fallback; keep explicit user mask config.
    self->mask_enabled = FALSE;
    self->mask_enabled_by_secure = FALSE;
    if (self->focus_out_timeout_id != 0) {
      g_source_remove(self->focus_out_timeout_id);
      self->focus_out_timeout_id = 0;
    }
    set_mask_visible(self, FALSE, "secure_disabled");
  }
  return xue_hua_screen_protection_screen_protection_host_api_set_secure_screen_response_new(
      TRUE);
}

static XueHuaScreenProtectionScreenProtectionHostApiIsSecureScreenEnabledResponse*
handle_is_secure_screen_enabled(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);
  return xue_hua_screen_protection_screen_protection_host_api_is_secure_screen_enabled_response_new(
      self->is_secure_screen_enabled);
}

static XueHuaScreenProtectionScreenProtectionHostApiConfigureAppSwitcherProtectionResponse*
handle_configure_app_switcher_protection(
    XueHuaScreenProtectionScreenProtectionMaskConfigMessage* config,
    gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);

  self->mask_enabled =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_enabled(
          config);
  self->mask_enabled_by_secure = FALSE;
  self->mask_style =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_style(
          config);
  self->mask_blur_sigma =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_blur_sigma(
          config);
  self->mask_background_color = static_cast<guint32>(
      xue_hua_screen_protection_screen_protection_mask_config_message_get_background_color(
          config));
  self->mask_text_color = static_cast<guint32>(
      xue_hua_screen_protection_screen_protection_mask_config_message_get_text_color(
          config));

  const gchar* title =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_title(
          config);
  g_free(self->mask_title);
  self->mask_title = g_strdup(
      (title != nullptr && title[0] != '\0') ? title : "Privacy Protected");

  const gchar* subtitle =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_subtitle(
          config);
  g_free(self->mask_subtitle);
  self->mask_subtitle = g_strdup(subtitle != nullptr ? subtitle : "");

  self->mask_show_lock_icon =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_show_lock_icon(
          config);
  self->protect_on_window_blur =
      xue_hua_screen_protection_screen_protection_mask_config_message_get_protect_on_window_blur(
          config);

  if (!self->mask_enabled ||
      self->mask_style ==
          XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_NONE) {
    if (self->focus_out_timeout_id != 0) {
      g_source_remove(self->focus_out_timeout_id);
      self->focus_out_timeout_id = 0;
    }
    set_mask_visible(self, FALSE, "config_disabled");
  } else {
    apply_mask_styles(self);
  }
  return xue_hua_screen_protection_screen_protection_host_api_configure_app_switcher_protection_response_new(
      TRUE);
}

static XueHuaScreenProtectionScreenProtectionHostApiConfigureWebProtectionResponse*
handle_configure_web_protection(
    XueHuaScreenProtectionWebProtectionConfigMessage* /*config*/,
    gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);
  return xue_hua_screen_protection_screen_protection_host_api_configure_web_protection_response_new(
      FALSE);
}

static XueHuaScreenProtectionScreenProtectionHostApiIsScreenBeingRecordedResponse*
handle_is_screen_being_recorded(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);
  return xue_hua_screen_protection_screen_protection_host_api_is_screen_being_recorded_response_new(
      FALSE);
}

static XueHuaScreenProtectionScreenProtectionHostApiGetProtectionStatusResponse*
handle_get_protection_status(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);

  g_autoptr(XueHuaScreenProtectionScreenProtectionStatusMessage) status =
      xue_hua_screen_protection_screen_protection_status_message_new(
          self->is_secure_screen_enabled,
          self->mask_enabled &&
              self->mask_style !=
                  XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_NONE,
          FALSE, self->is_mask_currently_visible, "linux");
  return xue_hua_screen_protection_screen_protection_host_api_get_protection_status_response_new(
      status);
}

static XueHuaScreenProtectionScreenProtectionHostApiGetCapabilitiesResponse*
handle_get_capabilities(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);

  g_autoptr(XueHuaScreenProtectionScreenProtectionCapabilitiesMessage) caps =
      get_linux_capabilities_message();
  return xue_hua_screen_protection_screen_protection_host_api_get_capabilities_response_new(
      caps);
}

static XueHuaScreenProtectionScreenProtectionHostApiShowPrivacyMaskResponse*
handle_show_privacy_mask(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);
  set_mask_visible(self, TRUE, "manual");
  return xue_hua_screen_protection_screen_protection_host_api_show_privacy_mask_response_new(
      TRUE);
}

static XueHuaScreenProtectionScreenProtectionHostApiHidePrivacyMaskResponse*
handle_hide_privacy_mask(gpointer user_data) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(user_data);
  ensure_window_signals_connected(self);
  set_mask_visible(self, FALSE, "manual");
  return xue_hua_screen_protection_screen_protection_host_api_hide_privacy_mask_response_new(
      TRUE);
}

static const XueHuaScreenProtectionScreenProtectionHostApiVTable
    kHostApiVTable = {
        handle_set_secure_screen,
        handle_is_secure_screen_enabled,
        handle_configure_app_switcher_protection,
        handle_configure_web_protection,
        handle_is_screen_being_recorded,
        handle_get_protection_status,
        handle_get_capabilities,
        handle_show_privacy_mask,
        handle_hide_privacy_mask,
};

static void xue_hua_screen_protection_plugin_dispose(GObject* object) {
  XueHuaScreenProtectionPlugin* self =
      XUE_HUA_SCREEN_PROTECTION_PLUGIN(object);
  if (self->focus_out_timeout_id != 0) {
    g_source_remove(self->focus_out_timeout_id);
    self->focus_out_timeout_id = 0;
  }
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
    if (self->size_allocate_handler_id > 0) {
      g_signal_handler_disconnect(self->tracked_window,
                                  self->size_allocate_handler_id);
      self->size_allocate_handler_id = 0;
    }
    self->tracked_window = nullptr;
  }
  if (self->mask_overlay != nullptr) {
    gtk_widget_destroy(self->mask_overlay);
    self->mask_overlay = nullptr;
    self->mask_title_label = nullptr;
    self->mask_subtitle_label = nullptr;
  }
  g_clear_object(&self->mask_css_provider);
  g_clear_object(&self->flutter_api);
  g_clear_object(&self->registrar);
  g_free(self->mask_title);
  self->mask_title = nullptr;
  g_free(self->mask_subtitle);
  self->mask_subtitle = nullptr;
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
  self->mask_enabled_by_secure = FALSE;
  self->mask_style =
      XUE_HUA_SCREEN_PROTECTION_SCREEN_PROTECTION_MASK_STYLE_MESSAGE_BLUR;
  self->mask_blur_sigma = 20.0;
  self->mask_background_color = 0xEB0F172A;
  self->mask_text_color = 0xFFFFFFFF;
  self->mask_title = g_strdup("Privacy Protected");
  self->mask_subtitle = g_strdup(
      "Screen content is hidden to protect sensitive information.");
  self->mask_show_lock_icon = TRUE;
  self->protect_on_window_blur = TRUE;
  self->mask_overlay = nullptr;
  self->mask_title_label = nullptr;
  self->mask_subtitle_label = nullptr;
  self->mask_css_provider = nullptr;
  self->size_allocate_handler_id = 0;
  self->focus_out_timeout_id = 0;
}

void xue_hua_screen_protection_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  XueHuaScreenProtectionPlugin* plugin = XUE_HUA_SCREEN_PROTECTION_PLUGIN(
      g_object_new(xue_hua_screen_protection_plugin_get_type(), nullptr));

  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

  plugin->flutter_api =
      xue_hua_screen_protection_screen_protection_flutter_api_new(messenger,
                                                                  nullptr);

  xue_hua_screen_protection_screen_protection_host_api_set_method_handlers(
      messenger, nullptr, &kHostApiVTable, g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);
}
