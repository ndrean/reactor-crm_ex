defmodule CrmReactor.Emails.PasswordResetEmailTest do
  use ExUnit.Case, async: true

  alias CrmReactor.Emails.PasswordResetEmail

  test "build/3 returns email with correct fields and greeting with name" do
    email = PasswordResetEmail.build("user@test.com", "Jean", "https://example.com/reset/abc")

    assert email.to == [{"", "user@test.com"}]
    assert email.subject == "Réinitialisation de votre mot de passe CRM Reactor"
    assert email.text_body =~ "Bonjour Jean,"
    assert email.text_body =~ "https://example.com/reset/abc"
    assert email.text_body =~ "24 heures"
  end

  test "build/3 with nil name uses generic greeting" do
    email = PasswordResetEmail.build("user@test.com", nil, "https://example.com/reset/abc")

    assert email.text_body =~ "Bonjour,"
    refute email.text_body =~ "Bonjour ,"
  end
end
