defmodule TcmMobile.Screens.MistakesScreen do
  @moduledoc "错题本 —— 按来源列出错题，支持查看解析与移除。"

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, Mob.Socket.assign(socket, :mistakes, Api.mistakes())}
  end

  @impl true
  def render(assigns) do
    cards = Enum.map(assigns.mistakes, &mistake_card/1)

    ~MOB"""
    <Column fill_height={true} background={:background}>
      {UI.detail_header("错题本")}
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {if @mistakes == [] do
            UI.empty_state("star_filled", "太棒了，没有错题！")
          else
            cards
          end}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
    </Column>
    """
  end

  defp mistake_card(m) do
    remove_tap = {self(), {:remove, m.id}}
    my = if m.my_answer, do: Enum.at(m.options, m.my_answer), else: "未作答"
    correct = Enum.at(m.options, m.correct_answer)

    UI.card(
      [
        %{
          type: :row,
          props: %{gap: :space_sm, align: :center},
          children: [
            %{
              type: :text,
              props: %{text: m.source, text_size: :xs, text_color: :muted, weight: 1},
              children: []
            },
            %{
              type: :box,
              props: %{on_tap: remove_tap, padding: :space_xs, corner_radius: :radius_pill},
              children: [
                %{
                  type: :icon,
                  props: %{name: "close", text_size: 16, text_color: :muted},
                  children: []
                }
              ]
            }
          ]
        },
        %{
          type: :text,
          props: %{
            text: m.question,
            text_size: :base,
            font_weight: "medium",
            text_color: :on_surface
          },
          children: []
        },
        %{
          type: :row,
          props: %{gap: :space_sm},
          children: [
            %{
              type: :box,
              props: %{
                background: 0x1FDC2626,
                corner_radius: :radius_md,
                padding: :space_sm,
                weight: 1
              },
              children: [
                %{
                  type: :text,
                  props: %{text: "你的答案：#{my}", text_size: :sm, text_color: :error},
                  children: []
                }
              ]
            },
            %{
              type: :box,
              props: %{
                background: 0x1F0F766E,
                corner_radius: :radius_md,
                padding: :space_sm,
                weight: 1
              },
              children: [
                %{
                  type: :text,
                  props: %{text: "正确答案：#{correct}", text_size: :sm, text_color: :secondary},
                  children: []
                }
              ]
            }
          ]
        },
        %{
          type: :text,
          props: %{text: m.explanation, text_size: :sm, text_color: :muted},
          children: []
        }
      ],
      gap: 8
    )
  end

  @impl true
  def handle_info({:tap, :back}, socket), do: {:noreply, Mob.Socket.pop_screen(socket)}

  def handle_info({:tap, {:remove, id}}, socket) do
    Api.clear_mistake(id)
    {:noreply, Mob.Socket.assign(socket, :mistakes, Api.mistakes())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
