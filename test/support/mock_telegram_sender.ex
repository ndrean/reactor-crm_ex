defmodule CrmReactor.Telegram.MockSender do
  @moduledoc "Telegram sender that always fails, for testing delivery error handling."

  def send_message(_chat_id, _text), do: {:error, :timeout}
  def send_confirmation(_chat_id, _text, _pending_id), do: {:error, :timeout}
end
