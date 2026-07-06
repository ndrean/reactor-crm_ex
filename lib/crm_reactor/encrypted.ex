defmodule CrmReactor.Encrypted.Binary do
  @moduledoc "Cloak encrypted binary type for Ecto."
  use Cloak.Ecto.Binary, vault: CrmReactor.Vault
end

defmodule CrmReactor.Encrypted.HMAC do
  @moduledoc "HMAC index type for searching encrypted fields."
  use Cloak.Ecto.HMAC, otp_app: :crm_reactor
end
