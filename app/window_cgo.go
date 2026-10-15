//go:build cgo

package main

/*
#cgo pkg-config: gtk+-3.0 webkit2gtk-4.1
#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <stdlib.h>

static void on_destroy(GtkWidget *widget, gpointer data) {
    gtk_main_quit();
}

static void setup_window(GtkWidget *window, GtkWidget *webview, const char *title, const char *icon_path, int width, int height) {
    gtk_window_set_title(GTK_WINDOW(window), title);
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);
    if (icon_path != NULL && g_file_test(icon_path, G_FILE_TEST_EXISTS)) {
        gtk_window_set_icon_from_file(GTK_WINDOW(window), icon_path, NULL);
    } else {
        gtk_window_set_icon_name(GTK_WINDOW(window), "weget");
    }
    gtk_container_add(GTK_CONTAINER(window), webview);
    g_signal_connect(window, "destroy", G_CALLBACK(on_destroy), NULL);
    gtk_widget_show_all(window);
}

static void load_uri(GtkWidget *webview, const char *uri) {
    webkit_web_view_load_uri(WEBKIT_WEB_VIEW(webview), uri);
}
*/
import "C"
import (
	"os"
	"unsafe"
)

func launchAppWindow(url, title, iconPath string, width, height int) {
	C.gtk_init(nil, nil)

	cTitle := C.CString(title)
	defer C.free(unsafe.Pointer(cTitle))

	cURL := C.CString(url)
	defer C.free(unsafe.Pointer(cURL))

	window := C.gtk_window_new(C.GTK_WINDOW_TOPLEVEL)
	webview := C.webkit_web_view_new()

	cIconPath := C.CString(iconPath)
	defer C.free(unsafe.Pointer(cIconPath))

	C.setup_window(window, webview, cTitle, cIconPath, C.int(width), C.int(height))
	C.load_uri(webview, cURL)

	C.gtk_main()
	os.Exit(0)
}
