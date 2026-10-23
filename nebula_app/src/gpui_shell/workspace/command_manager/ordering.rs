//! Browse-only order controls; the store owns membership and neighbor selection.

use super::*;
use crate::i18n::Message;
use crate::saved_commands::{BUILTIN_GROUP_ID, MoveDirection};
use gpui::AnyElement;

#[derive(Clone)]
pub(super) enum OrderTarget {
    Command(String),
    Group(String),
}

impl NebulaWorkspace {
    fn command_order_available(&self, cx: &App) -> bool {
        !self.command_manager_selection.selecting
            && self.command_manager_input.read(cx).value().trim().is_empty()
    }

    pub(super) fn render_command_order_buttons(
        &self,
        target: OrderTarget,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        if !self.command_order_available(cx) {
            return None;
        }
        let (kind, id) = match &target {
            OrderTarget::Command(id) if !id.starts_with("builtin:") => ("command", id),
            OrderTarget::Group(id) if id != BUILTIN_GROUP_ID => ("group", id),
            _ => return None,
        };
        let language = crate::gpui_shell::config::ui_language(cx);
        let mut controls = h_flex().flex_shrink_0().gap_1();
        for (direction, name, icon, message) in [
            (MoveDirection::Up, "up", IconName::ArrowUp, Message::CommandsMoveUp),
            (MoveDirection::Down, "down", IconName::ArrowDown, Message::CommandsMoveDown),
        ] {
            let enabled = match &target {
                OrderTarget::Command(id) => self.saved_commands.can_reorder_command(id, direction),
                OrderTarget::Group(id) => self.saved_commands.can_reorder_group(id, direction),
            };
            let selector = format!("{kind}-move-{name}-{id}");
            let keyboard_target = target.clone();
            let click_target = target.clone();
            controls = controls.child(
                Button::new(SharedString::from(selector.clone()))
                    .debug_selector(move || selector.clone())
                    .icon(Icon::new(icon).size(px(ROW_ICON_SIZE)))
                    .ghost()
                    .xsmall()
                    .size(px(32.0))
                    .aria_label(language.text(message))
                    .tooltip(language.text(message))
                    .disabled(!enabled)
                    .when(enabled, |control| {
                        control.on_key_down(cx.listener(
                            move |this, event: &KeyDownEvent, window, cx| {
                                if matches!(event.keystroke.key.as_str(), "enter" | "space") {
                                    cx.stop_propagation();
                                    this.reorder_command_target(
                                        &keyboard_target,
                                        direction,
                                        window,
                                        cx,
                                    );
                                }
                            },
                        ))
                    })
                    .on_click(cx.listener(move |this, _, window, cx| {
                        cx.stop_propagation();
                        this.reorder_command_target(&click_target, direction, window, cx);
                    })),
            );
        }
        Some(controls.into_any_element())
    }

    fn reorder_command_target(
        &mut self,
        target: &OrderTarget,
        direction: MoveDirection,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if !self.command_order_available(cx) {
            return;
        }
        let result = match target {
            OrderTarget::Command(id) => self.saved_commands.reorder_command(id, direction),
            OrderTarget::Group(id) => self.saved_commands.reorder_group(id, direction),
        };
        if let Err(error) = result {
            let language = crate::gpui_shell::config::ui_language(cx);
            crate::gpui_shell::toast::toast(
                window,
                cx,
                crate::display::ToastKind::Warning,
                language.format(Message::CommandsOrderSaveFailed, &[("error", &error.to_string())]),
            );
            return;
        }
        if let Some(index) =
            self.command_manager_rows(cx).iter().position(|row| match (target, row) {
                (OrderTarget::Command(id), ManagerRow::Command(command)) => id == &command.id,
                (OrderTarget::Group(id), ManagerRow::Folder { id: group, .. }) => id == group,
                _ => false,
            })
        {
            self.command_manager_selection.cursor = index;
            self.command_manager_scroll.scroll_to_item(index, gpui::ScrollStrategy::Nearest);
        }
        cx.notify();
    }
}
