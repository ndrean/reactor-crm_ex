# Reactor v1.0 Cheatsheet

Source: <https://reactor.hexdocs.pm/reactor-cheatsheet.html>

## Basic structure

```elixir
defmodule MyReactor do
  use Reactor

  input :email
  input :password

  step :hash_password do
    argument :password, input(:password)
    run &Bcrypt.hash_pwd_salt/1
  end

  return :hash_password
end

Reactor.run(MyReactor, email: "...", password: "...")
```

## Argument sources

```elixir
argument :x, input(:name)           # reactor input
argument :x, result(:step_name)     # step output
argument :x, value("literal")       # static value
argument :x, result(:step, [:id])   # path extraction
argument :x, result(:y) do          # inline transform
  transform &(&1.id)
end
```

## wait_for

Order steps without passing data:

```elixir
step :classification, ClassifyIntent do
  argument :text, result(:text)
  wait_for :tenant                   # don't classify until tenant is resolved
end
```

Desugars to `argument :_, result(:tenant)`.

## Step module

```elixir
defmodule MyStep do
  use Reactor.Step

  def run(arguments, context, options), do: {:ok, result}
  def compensate(reason, arguments, context, options), do: :retry | :ok
  def undo(value, arguments, context, options), do: :ok | {:error, reason}
end
```

### Return values from run/3

- `{:ok, value}` -- success
- `{:ok, value, [additional_steps]}` -- success with dynamic steps
- `{:error, reason}` -- failure, triggers compensation
- `:retry` or `{:retry, reason}` -- retry the step
- `{:halt, reason}` -- pause reactor

## switch

```elixir
switch :route, on: result(:classification) do
  matches? &(&1.workflow == "contacts") do
    step :contacts_result, ContactsStep do
      argument :data, result(:classification)
    end
    return :contacts_result
  end

  matches? &(&1.workflow == "todos") do
    step :todos_result, TodosStep do
      argument :data, result(:classification)
    end
    return :todos_result
  end

  default do
    step :help, HelpStep
    return :help
  end
end
```

## map (process collections)

```elixir
map :process_items do
  source result(:items)
  batch_size 10

  step :transform_item, TransformStep do
    argument :item, element(:process_items)
  end

  return :transform_item
end
```

## collect (gather multiple results)

```elixir
collect :all_results do
  argument :a, result(:step_a)
  argument :b, result(:step_b)
  transform &Map.values/1
end
```

## compose (embed another reactor)

```elixir
compose :sub_pipeline, SubReactor do
  argument :input, result(:previous_step)
end
```

## group (lifecycle hooks)

```elixir
group :batch, before_all: &setup/1, after_all: &teardown/1 do
  step :work, WorkStep
end
```

## around (wrap in transaction)

```elixir
around :in_transaction, &Repo.transaction/1 do
  step :insert, InsertStep
end
```

## Options

```elixir
step :my_step, MyStep do
  async? false           # disable concurrent execution
  max_retries 3          # limit retries (default: :infinity)
end
```

## Debug

```elixir
debug :inspect_value do
  argument :value, result(:some_step)
end
```
