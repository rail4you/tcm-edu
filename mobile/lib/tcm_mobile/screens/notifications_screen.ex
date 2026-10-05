defmodule TcmMobile.Screens.NotificationsScreen do
  @moduledoc "通知中心。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :notifications, Api.notifications())}
  end

  @impl true
  def render(assigns) do
    cards = Enum.map(assigns.notifications, &notification_card/1)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("通知")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_sm} fill_width={true}>
          {cards}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp notification_card(n) do
    dot =
      if n.read do
        %{type: :spacer, props: %{}, children: []}
      else
        %{
          type: :box,
          props: %{width: 8, height: 8, corner_radius: :radius_pill, background: :primary},
          children: []
        }
      end

    UI.card(
      [
        %{
          type: :row,
          props: %{gap: :space_sm, align: :center},
          children: [
            %{
              type: :text,
              props: %{
                text: n.title,
                text_size: :base,
                font_weight: if(n.read, do: "regular", else: "medium"),
                text_color: :on_surface,
                weight: 1
              },
              children: []
            },
            dot
          ]
        },
        %{type: :text, props: %{text: n.body, text_size: :sm, text_color: :muted}, children: []},
        %{type: :text, props: %{text: n.time, text_size: :xs, text_color: :muted}, children: []}
      ],
      gap: 6
    )
  end

  @impl true
  def handle_info({:tap, :back}, socket) do
    Api.mark_notifications_read()
    {:noreply, Mob.Socket.pop_screen(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
