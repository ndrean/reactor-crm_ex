defmodule CrmReactor.Vault do
  @moduledoc "Cloak vault for encrypting PII fields (email, phone)."
  use Cloak.Vault, otp_app: :crm_reactor
end
