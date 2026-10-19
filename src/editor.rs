use std::cell::RefCell;
use std::rc::Rc;

use objc2::rc::Retained;
use objc2::{define_class, msg_send, sel, MainThreadOnly};
use objc2_app_kit::{
    NSApplication, NSBackingStoreType, NSButton, NSTextField, NSWindow, NSWindowStyleMask,
};
use objc2_foundation::{
    ns_string, MainThreadMarker, NSObject, NSObjectProtocol, NSPoint, NSRect, NSSize, NSString,
};
use tray_icon::TrayIcon;

const MAX_TITLE_LEN: usize = 40;

struct EditorState {
    window: Retained<NSWindow>,
    field: Retained<NSTextField>,
    tray: TrayIcon,
    title: Rc<RefCell<String>>,
    #[allow(dead_code)]
    handler: Retained<CommitHandler>,
}

thread_local! {
    static EDITOR: RefCell<Option<EditorState>> = const { RefCell::new(None) };
}

define_class!(
    #[unsafe(super = NSObject)]
    #[thread_kind = MainThreadOnly]
    struct CommitHandler;

    unsafe impl NSObjectProtocol for CommitHandler {}

    impl CommitHandler {
        #[unsafe(method(commit:))]
        fn commit(&self, _sender: &NSObject) {
            EDITOR.with(|cell| {
                if let Some(state) = cell.borrow_mut().take() {
                    let text = sanitize_title(&state.field.stringValue().to_string());
                    *state.title.borrow_mut() = text.clone();
                    state.tray.set_title(Some(text));
                    state.window.close();
                }
            });
        }
    }
);

impl CommitHandler {
    fn new(mtm: MainThreadMarker) -> Retained<Self> {
        let this = Self::alloc(mtm);
        unsafe { msg_send![this, init] }
    }
}

/// Normalize text for display in the menu bar: single line, trimmed, and
/// truncated so it stays "short". Whitespace-only input falls back to "...".
pub fn sanitize_title(input: &str) -> String {
    let one_line: String = input
        .chars()
        .map(|c| if c == '\n' || c == '\r' || c == '\t' { ' ' } else { c })
        .collect();
    let trimmed: String = one_line.trim().chars().take(MAX_TITLE_LEN).collect();
    if trimmed.is_empty() {
        "...".to_string()
    } else {
        trimmed
    }
}

pub fn open_editor(tray: &TrayIcon, title: Rc<RefCell<String>>) {
    let mtm = MainThreadMarker::new().expect("open_editor must be called on the main thread");

    EDITOR.with(|cell| {
        if let Some(state) = cell.borrow().as_ref() {
            state
                .field
                .setStringValue(&NSString::from_str(&state.title.borrow()));
            state.window.makeKeyAndOrderFront(None);
            NSApplication::sharedApplication(mtm).activate();
            return;
        }

        let handler = CommitHandler::new(mtm);

        let window = unsafe {
            NSWindow::initWithContentRect_styleMask_backing_defer(
                NSWindow::alloc(mtm),
                NSRect::new(NSPoint::new(0.0, 0.0), NSSize::new(380.0, 120.0)),
                NSWindowStyleMask::Titled | NSWindowStyleMask::Closable,
                NSBackingStoreType::Buffered,
                false,
            )
        };
        unsafe { window.setReleasedWhenClosed(false) };
        window.setTitle(ns_string!("Edit text"));

        let field = NSTextField::initWithFrame(
            NSTextField::alloc(mtm),
            NSRect::new(NSPoint::new(20.0, 60.0), NSSize::new(340.0, 24.0)),
        );
        field.setStringValue(&NSString::from_str(&title.borrow()));
        unsafe {
            field.setTarget(Some(&handler));
            field.setAction(Some(sel!(commit:)));
        }

        let button = unsafe {
            NSButton::buttonWithTitle_target_action(
                ns_string!("Save"),
                Some(&handler),
                Some(sel!(commit:)),
                mtm,
            )
        };
        button.setFrame(NSRect::new(NSPoint::new(280.0, 20.0), NSSize::new(80.0, 32.0)));

        let content = window
            .contentView()
            .expect("window must have a content view");
        content.addSubview(&field);
        content.addSubview(&button);

        window.center();
        window.makeKeyAndOrderFront(None);
        NSApplication::sharedApplication(mtm).activate();

        *cell.borrow_mut() = Some(EditorState {
            window,
            field,
            tray: tray.clone(),
            title,
            handler,
        });
    });
}

#[cfg(test)]
mod tests {
    use super::sanitize_title;

    #[test]
    fn trims_whitespace() {
        assert_eq!(sanitize_title("  hello  "), "hello");
    }

    #[test]
    fn flattens_newlines_and_tabs() {
        assert_eq!(sanitize_title("a\nb\tc"), "a b c");
    }

    #[test]
    fn truncates_to_max_length() {
        let long = "x".repeat(100);
        assert_eq!(sanitize_title(&long).chars().count(), 40);
    }

    #[test]
    fn whitespace_only_falls_back_to_ellipsis() {
        assert_eq!(sanitize_title("   \n\t  "), "...");
    }

    #[test]
    fn empty_input_falls_back_to_ellipsis() {
        assert_eq!(sanitize_title(""), "...");
    }
}
