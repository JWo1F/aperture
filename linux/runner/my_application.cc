#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  // FlView's own child, which owns the pointer input.
  GtkWidget* event_box;
  FlMethodChannel* window_channel;
  // The press that started a toolbar pan: a move drag is begun with its
  // button, time and root position.
  GdkEvent* last_press;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// "event" rather than "button-press-event": it runs before the view's own
// press handler, which returns TRUE and so stops that signal's emission.
static gboolean event_cb(GtkWidget* widget, GdkEvent* event,
                         MyApplication* self) {
  if (gdk_event_get_event_type(event) == GDK_BUTTON_PRESS) {
    g_clear_pointer(&self->last_press, gdk_event_free);
    self->last_press = gdk_event_copy(event);
  }
  return FALSE;
}

static void start_drag(MyApplication* self) {
  if (self->last_press == nullptr) return;
  GdkEventButton* press = &self->last_press->button;
  gtk_window_begin_move_drag(self->window, press->button,
                             static_cast<gint>(press->x_root),
                             static_cast<gint>(press->y_root), press->time);
  // The window manager takes the pointer grab, so the view never sees this
  // button come up and Flutter would keep the pan alive. Release it here.
  GdkEvent* release = gdk_event_copy(self->last_press);
  release->button.type = GDK_BUTTON_RELEASE;
  gtk_widget_event(self->event_box, release);
  gdk_event_free(release);
}

static void window_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(call);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "startDrag") == 0) {
    start_drag(self);
  } else if (g_strcmp0(method, "toggleZoom") == 0) {
    if (gtk_window_is_maximized(self->window)) {
      gtk_window_unmaximize(self->window);
    } else {
      gtk_window_maximize(self->window);
    }
  } else if (g_strcmp0(method, "minimize") == 0) {
    gtk_window_iconify(self->window);
  } else if (g_strcmp0(method, "close") == 0) {
    // delete-event, which the engine turns into an app-exit request — the
    // same path as the window manager's close, so the quit guard runs.
    gtk_window_close(self->window);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  if (response == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }
  fl_method_call_respond(call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// The same two steps the engine takes for its render context. A VM without
// 3D acceleration fails them, and the engine then never draws a frame — so
// the window, shown on the first frame, never appears.
static gboolean gl_available(GtkWindow* window) {
  gtk_widget_realize(GTK_WIDGET(window));
  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkGLContext) context =
      gdk_window_create_gl_context(gtk_widget_get_window(GTK_WIDGET(window)),
                                   &error);
  if (context == nullptr || !gdk_gl_context_realize(context, &error)) {
    g_warning("OpenGL unavailable (%s); using the software renderer",
              error->message);
    return FALSE;
  }
  return TRUE;
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // The toolbar is the title bar, as on macOS. An invisible custom titlebar
  // keeps GTK's client-side decorations — shadow and resize edges — which
  // gtk_window_set_decorated(FALSE) would drop along with the frame.
  gtk_window_set_title(window, "Aperture");
  gtk_window_set_titlebar(window, gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  gtk_window_set_default_size(window, 1280, 720);

  // An explicit FLUTTER_LINUX_RENDERER wins; the engine reads the variable
  // itself when the view is created below.
  if (g_getenv("FLUTTER_LINUX_RENDERER") == nullptr && !gl_available(window)) {
    g_setenv("FLUTTER_LINUX_RENDERER", "software", TRUE);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
  // The engine's software renderer draws through Skia and aborts on
  // Impeller's text ("Impeller DlText cannot be drawn to a Skia canvas"),
  // and a release build ignores FLUTTER_ENGINE_SWITCHES, so the runner is
  // the only place left to turn Impeller off for it.
  if (g_strcmp0(g_getenv("FLUTTER_LINUX_RENDERER"), "software") == 0) {
    fl_dart_project_set_enable_impeller(project, FALSE);
  }

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  self->window = window;
  g_autoptr(GList) children = gtk_container_get_children(GTK_CONTAINER(view));
  self->event_box = GTK_WIDGET(children->data);
  g_signal_connect(self->event_box, "event", G_CALLBACK(event_cb), self);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "aperture/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_method_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->last_press, gdk_event_free);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
