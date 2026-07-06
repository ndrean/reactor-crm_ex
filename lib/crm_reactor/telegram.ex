defmodule CrmReactor.Telegram do
  @moduledoc "Telegram message sending and inline keyboard helpers."
  def send_message(chat_id, text) do
    Telegex.send_message(String.to_integer(chat_id), text)
  end

  def send_confirmation(chat_id, text, pending_id) do
    keyboard = %Telegex.Type.InlineKeyboardMarkup{
      inline_keyboard: [
        [
          %Telegex.Type.InlineKeyboardButton{
            text: "✅ Confirmer",
            callback_data: "#{pending_id}:confirm"
          },
          %Telegex.Type.InlineKeyboardButton{
            text: "❌ Annuler",
            callback_data: "#{pending_id}:reject"
          }
        ]
      ]
    }

    Telegex.send_message(String.to_integer(chat_id), text, reply_markup: keyboard)
  end
end
