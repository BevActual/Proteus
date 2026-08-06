//! ext-session-lock surface via iced_sessionlock (PROTEUS_SESSION_LOCK=protocol).
//!
//! Shares full-bleed lock UI with proteus-shell overlay path.

use iced::{Element, Task};
use iced_sessionlock::application;
use iced_sessionlock::to_session_message;

use proteus_shell::lock_ui::{self, LockMsg, LockUiState};
use proteus_shell::platform;
use proteus_ui::theme::Theme;

fn main() -> Result<(), iced_sessionlock::Error> {
    application(LockApp::new, LockApp::update, LockApp::view).run()
}

struct LockApp {
    theme: Theme,
    ui: LockUiState,
}

#[to_session_message]
#[derive(Debug, Clone)]
enum Message {
    Lock(LockMsg),
}

impl LockApp {
    fn new() -> (Self, Task<Message>) {
        (
            Self {
                theme: Theme::from_mode("dark", None),
                ui: LockUiState::default(),
            },
            Task::none(),
        )
    }

    fn try_unlock(&mut self) -> Task<Message> {
        self.ui.clear_expired_cooldown();
        if self.ui.cooldown_secs() > 0 {
            let left = self.ui.cooldown_secs().max(1);
            self.ui.status = format!("Cooldown · {left}s");
            return Task::none();
        }
        match platform::try_unlock(&self.ui.pin) {
            Ok(()) => {
                let _ = std::process::Command::new("proteus-shellctl")
                    .args(["lock", "unlock"])
                    .spawn();
                self.ui.on_success();
                Task::done(Message::UnLock)
            }
            Err(_) => {
                self.ui.on_fail();
                Task::none()
            }
        }
    }

    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Lock(LockMsg::Reveal) => {
                self.ui.reveal = true;
                Task::none()
            }
            Message::Lock(LockMsg::PinDigit(ch)) => {
                if self.ui.push_digit(ch) {
                    return self.try_unlock();
                }
                Task::none()
            }
            Message::Lock(LockMsg::PinBackspace) => {
                self.ui.pin.pop();
                Task::none()
            }
            Message::Lock(LockMsg::PinClear) => {
                self.ui.pin.clear();
                Task::none()
            }
            Message::Lock(LockMsg::UsePassword) => {
                self.ui.use_password = true;
                self.ui.pin.clear();
                self.ui.reveal = true;
                Task::none()
            }
            Message::Lock(LockMsg::UsePin) => {
                self.ui.use_password = false;
                self.ui.pin.clear();
                self.ui.reveal = true;
                Task::none()
            }
            Message::Lock(LockMsg::PinEntry(p)) => {
                if !self.ui.reveal {
                    self.ui.reveal = true;
                }
                self.ui.pin = p;
                Task::none()
            }
            Message::Lock(LockMsg::CustomizeAdd(k)) => {
                self.ui.customize_add(&k);
                Task::none()
            }
            Message::Lock(LockMsg::CustomizeRemove(id)) => {
                self.ui.customize_remove(&id);
                Task::none()
            }
            Message::Lock(LockMsg::CustomizeMove(id, d)) => {
                self.ui.customize_move(&id, d);
                Task::none()
            }
            Message::Lock(LockMsg::CustomizeDone) => {
                self.ui.customize = false;
                Task::none()
            }
            Message::Lock(LockMsg::Unlock) => self.try_unlock(),
            Message::UnLock => Task::done(message),
        }
    }

    fn view(&self, _id: iced::window::Id) -> Element<'_, Message> {
        lock_ui::lock_screen_view(&self.theme, &self.ui).map(Message::Lock)
    }
}
