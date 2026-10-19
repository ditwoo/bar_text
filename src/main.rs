use std::cell::RefCell;
use std::rc::Rc;

use tao::event::{Event, StartCause};
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tray_icon::menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem};
use tray_icon::{TrayIcon, TrayIconBuilder};

const DEFAULT_TITLE: &str = "Hello";

enum UserEvent {
    Menu(MenuEvent),
}

fn main() {
    let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();

    let proxy = event_loop.create_proxy();
    MenuEvent::set_event_handler(Some(move |event| {
        let _ = proxy.send_event(UserEvent::Menu(event));
    }));
 
    let menu = Menu::new();
    let edit_item = MenuItem::with_id("edit", "Edit text", true, None);
    let quit_item = PredefinedMenuItem::quit(Some("Quit"));
    menu.append_items(&[&edit_item, &quit_item])
        .expect("failed to build menu");

    let mut tray: Option<TrayIcon> = None;

    let title = Rc::new(RefCell::new(DEFAULT_TITLE.to_string()));

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        match event {
            Event::NewEvents(StartCause::Init) => {
                #[cfg(target_os = "macos")]
                {
                    use objc2_app_kit::{NSApplication, NSApplicationActivationPolicy};
                    use objc2_foundation::MainThreadMarker;

                    if let Some(mtm) = MainThreadMarker::new() {
                        // Status-bar-only utility: no Dock icon, no app menu.
                        NSApplication::sharedApplication(mtm)
                            .setActivationPolicy(NSApplicationActivationPolicy::Accessory);
                    }
                }

                tray = Some(
                    TrayIconBuilder::new()
                        .with_title(title.borrow().as_str())
                        .with_tooltip("bar-text")
                        .with_autosave_name("bar-text")
                        .with_menu(Box::new(menu.clone()))
                        .build()
                        .expect("failed to create tray icon"),
                );

                #[cfg(target_os = "macos")]
                {
                    use objc2_core_foundation::CFRunLoop;
                    if let Some(rl) = CFRunLoop::main() {
                        CFRunLoop::wake_up(&rl);
                    }
                }
            }

            Event::UserEvent(UserEvent::Menu(event)) => {
                if event.id == edit_item.id() {
                    if let Some(tray) = tray.as_ref() {
                        editor::open_editor(tray, Rc::clone(&title));
                    }
                } else if event.id == quit_item.id() {
                    *control_flow = ControlFlow::Exit;
                }
            }

            _ => {}
        }
    });
}

mod editor;
