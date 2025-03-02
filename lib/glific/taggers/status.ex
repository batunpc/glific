defmodule Glific.Taggers.Status do
  @moduledoc """
  This module will be responsible for all the contact and message status tagging. Like new contact tag and unread
  """

  @doc false
  @spec get_status_map(map()) :: %{String.t() => integer}
  def get_status_map(%{organization_id: _organization_id} = attrs),
    do: Glific.Tags.status_map(attrs)

  @doc false
  @spec is_new_contact(integer()) :: boolean()
  def is_new_contact(contact_id), do: Glific.Contacts.is_new_contact(contact_id)
end
