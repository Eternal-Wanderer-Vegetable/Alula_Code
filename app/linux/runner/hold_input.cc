#include "hold_input.h"

#include <array>
#include <cstdint>

#include <gtk/gtk.h>

#if defined(GDK_WINDOWING_X11) && defined(ALULA_X11_HOLD_INPUT)
#include <X11/extensions/XInput2.h>
#include <gdk/gdkx.h>
#endif

namespace {

#if defined(GDK_WINDOWING_X11) && defined(ALULA_X11_HOLD_INPUT)

// GTK and the Flutter runners share the application's X11 connection. Keep
// only recent key-down metadata to correlate a Flutter key-down with XI2.
struct ObservedPress {
  Window window = None;
  uint32_t time = 0;
  int scan_code = 0;
  bool repeat = false;
};

std::array<ObservedPress, 128> recent_presses;
size_t next_press = 0;
int xi_opcode = -1;

GdkFilterReturn ObserveX11Key(GdkXEvent* xevent, GdkEvent*, gpointer data) {
  const auto* event = static_cast<const XEvent*>(xevent);
  if (event->type == GenericEvent && event->xcookie.extension == xi_opcode &&
      event->xcookie.evtype == XI_KeyPress && event->xcookie.data != nullptr) {
    const auto* key = static_cast<const XIDeviceEvent*>(event->xcookie.data);
    GdkWindow* target = gdk_x11_window_lookup_for_display(
        GDK_DISPLAY(data), key->event);
    if (target == nullptr) return GDK_FILTER_CONTINUE;
    // The physical event may target a native child of the Flutter window.
    GdkWindow* top = gdk_window_get_effective_toplevel(target);
    recent_presses[next_press] = {
        gdk_x11_window_get_xid(top), static_cast<uint32_t>(key->time),
        key->detail, (key->flags & XIKeyRepeat) != 0};
    next_press = (next_press + 1) % recent_presses.size();
  }
  return GDK_FILTER_CONTINUE;
}

bool IsFreshX11Press(GtkWidget* view, int64_t scan_code, int64_t time_us) {
  GtkWidget* top = gtk_widget_get_toplevel(view);
  GdkWindow* window = gtk_widget_get_window(top);
  if (window == nullptr || !GDK_IS_X11_WINDOW(window)) return true;
  if (!gtk_window_is_active(GTK_WINDOW(top))) return false;
  const auto xid = gdk_x11_window_get_xid(window);
  const auto time = static_cast<uint32_t>(time_us / 1000);
  auto index = next_press;
  for (size_t i = 0; i < recent_presses.size(); ++i) {
    index = (index + recent_presses.size() - 1) % recent_presses.size();
    const auto& press = recent_presses[index];
    if (press.window == xid && press.time == time &&
        press.scan_code == scan_code) {
      return !press.repeat;
    }
  }
  return true;
}

void ReleaseView(gpointer data) {
  auto* reference = static_cast<GWeakRef*>(data);
  g_weak_ref_clear(reference);
  delete reference;
}

void OnHoldInput(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  if (g_strcmp0(fl_method_call_get_name(call), "isFreshHoldPress") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_LIST ||
      fl_value_get_length(args) != 2 ||
      fl_value_get_type(fl_value_get_list_value(args, 0)) != FL_VALUE_TYPE_INT ||
      fl_value_get_type(fl_value_get_list_value(args, 1)) != FL_VALUE_TYPE_INT) {
    fl_method_call_respond_error(call, "invalid-arguments",
                                 "Expected a scan code and timestamp", nullptr,
                                 nullptr);
    return;
  }
  g_autoptr(GObject) view =
      G_OBJECT(g_weak_ref_get(static_cast<GWeakRef*>(data)));
  g_autoptr(FlValue) fresh = fl_value_new_bool(
      view != nullptr && IsFreshX11Press(
                             GTK_WIDGET(view),
                             fl_value_get_int(fl_value_get_list_value(args, 0)),
                             fl_value_get_int(fl_value_get_list_value(args, 1))));
  fl_method_call_respond_success(call, fresh, nullptr);
}

#endif

}  // namespace

void RegisterHoldInputChannel(FlView* view) {
#if defined(GDK_WINDOWING_X11) && defined(ALULA_X11_HOLD_INPUT)
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(view));
  if (!GDK_IS_X11_DISPLAY(display)) return;
  if (xi_opcode < 0) {
    int first_event;
    int first_error;
    if (!XQueryExtension(gdk_x11_display_get_xdisplay(display),
                         "XInputExtension", &xi_opcode, &first_event,
                         &first_error)) {
      xi_opcode = -1;
      return;
    }
    gdk_window_add_filter(nullptr, ObserveX11Key, display);
  }
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "alula/hold_input", FL_METHOD_CODEC(codec));
  auto* reference = new GWeakRef;
  g_weak_ref_init(reference, G_OBJECT(view));
  fl_method_channel_set_method_call_handler(channel, OnHoldInput, reference,
                                          ReleaseView);
#else
  (void)view;
#endif
}
