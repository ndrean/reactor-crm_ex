defmodule CrmReactor.Reactors.MasterIngestTest do
  use CrmReactor.DataCase

  alias CrmReactor.TestFixtures

  setup do
    fixture = TestFixtures.provision_test_tenant()
    on_exit(fn -> TestFixtures.cleanup_tenant(fixture) end)
    fixture
  end

  test "search contacts by name", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "cherche Marie",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil
      })

    assert result.output =~ "Marie"
    assert result.output =~ "Dupont"
  end

  test "count contacts", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "combien de contacts",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil
      })

    assert result.output =~ "2"
  end

  test "list todos", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "liste mes tâches",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil
      })

    assert result.output =~ "Appeler fournisseur"
  end

  test "unknown user rejected" do
    assert {:error, %{errors: [%{error: :unknown_user} | _]}} =
             Reactor.run(CrmReactor.Reactors.MasterIngest, %{
               user_id: "0000000000",
               raw_input: "hello",
               is_audio: false,
               channel: :http,
               job_id: nil,
               attachment: nil
             })
  end

  test "help / unrecognized input returns help message", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "blablabla",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil
      })

    assert result.output =~ "contacts"
  end

  test "mutation requires confirmation", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "supprime Marie Dupont",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil
      })

    assert result.action == "pending"
    assert result.pending_id != nil
  end

  test "data export without admin_email asks for email via pending loop", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "exporte les données",
        is_audio: false,
        channel: :http,
        job_id: "http-#{Ecto.UUID.generate()}",
        attachment: nil
      })

    assert result.action == "pending"
    assert result.pending_id != nil
    assert result.output =~ "email"
  end

  test "multi-intent message executes both steps and combines output", %{user_id: user_id} do
    {:ok, result} =
      Reactor.run(CrmReactor.Reactors.MasterIngest, %{
        user_id: user_id,
        raw_input: "ajoute le contact John Doe et ajoute la tâche de l'appeler",
        is_audio: false,
        channel: :http,
        job_id: nil,
        attachment: nil
      })

    assert result.output =~ "Contact créé"
    assert result.output =~ "Tâche créée"
  end
end
