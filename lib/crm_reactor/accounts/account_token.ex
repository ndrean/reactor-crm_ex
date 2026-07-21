defmodule CrmReactor.Accounts.AccountToken do
  use Ecto.Schema
  import Ecto.Query

  @schema_prefix "global_registry"

  @rand_size 32
  @session_validity_in_days 60
  @invite_validity_in_hours 24
  @magic_link_validity_in_minutes 15
  @calendar_validity_in_days 365

  schema "account_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :account, CrmReactor.Accounts.Account

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def build_session_token(account) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: token, context: "session", account_id: account.id}}
  end

  def build_invite_token(account) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: token,
       context: "invite",
       sent_to: account.email,
       account_id: account.id
     }}
  end

  def verify_session_token_query(token) do
    from t in __MODULE__,
      where: t.token == ^token and t.context == "session",
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      join: a in assoc(t, :account),
      select: a
  end

  def build_magic_link_token(account) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: token,
       context: "magic_link",
       sent_to: account.email,
       account_id: account.id
     }}
  end

  def verify_magic_link_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, token} ->
        query =
          from t in __MODULE__,
            where: t.token == ^token and t.context == "magic_link",
            where: t.inserted_at > ago(@magic_link_validity_in_minutes, "minute"),
            join: a in assoc(t, :account),
            select: a

        {:ok, query}

      :error ->
        :error
    end
  end

  def build_calendar_token(account) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: token,
       context: "calendar",
       sent_to: account.email,
       account_id: account.id
     }}
  end

  def verify_calendar_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, token} ->
        query =
          from t in __MODULE__,
            where: t.token == ^token and t.context == "calendar",
            where: t.inserted_at > ago(@calendar_validity_in_days, "day"),
            join: a in assoc(t, :account),
            where: is_nil(a.suspended_at),
            select: a

        {:ok, query}

      :error ->
        :error
    end
  end

  def verify_invite_token_query(encoded_token) do
    case Base.url_decode64(encoded_token, padding: false) do
      {:ok, token} ->
        query =
          from t in __MODULE__,
            where: t.token == ^token and t.context == "invite",
            where: t.inserted_at > ago(@invite_validity_in_hours, "hour"),
            join: a in assoc(t, :account),
            select: a

        {:ok, query}

      :error ->
        :error
    end
  end
end
