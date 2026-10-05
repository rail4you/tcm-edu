defmodule TcmMobile.Screens.CoursesScreen do
  @moduledoc """
  课程 tab —— 分类筛选 + 搜索 + 课程列表。
  """

  use Mob.Screen

  alias TcmMobile.{Api, UI}

  @impl true
  def mount(params, _session, socket) do
    category = params[:category] || "all"

    {:ok,
     socket
     |> Mob.Socket.assign(:categories, [%{id: "all", name: "全部"} | Api.list_categories()])
     |> Mob.Socket.assign(:category, category)
     |> Mob.Socket.assign(:query, "")
     |> Mob.Socket.assign(:courses, load_courses(category, ""))}
  end

  defp load_courses(category, query) do
    if query == "" do
      Api.list_courses(if(category == "all", do: nil, else: category))
    else
      Api.search_courses(query)
    end
  end

  @impl true
  def render(assigns) do
    courses = assigns.courses
    category = assigns.category

    chips =
      Enum.map(assigns.categories, fn c ->
        selected = c.id == category
        UI.chip(c.name, selected) |> put_tap({self(), {:category, c.id}})
      end)

    cards =
      Enum.map(courses, fn c ->
        UI.course_card(c, {self(), {:course, c.id}}, Api.enrolled?(c.id))
      end)

    empty =
      if courses == [] do
        UI.empty_state("search", "没有找到匹配的课程")
      else
        %{type: :spacer, props: %{}, children: []}
      end

    ~MOB"""
    <Column fill_height={true} background={:background}>
      <Scroll weight={1} padding={:space_lg} fill_width={true}>
        <Column gap={:space_md} fill_width={true}>
          {UI.app_bar("课程")}
          <TextField value={assigns.query} placeholder="搜索课程 / 标签" on_change={{self(), :search}} />
          <Scroll axis="horizontal" fill_width={true}>
            <Row gap={:space_sm} fill_width={false}>
              {chips}
            </Row>
          </Scroll>
          <Text text={"共 #{length(courses)} 门课程"} text_size={:xs} text_color={:muted} />
          {cards}
          {empty}
          <Spacer size={:space_lg} />
        </Column>
      </Scroll>
      {UI.tab_bar(:courses)}
    </Column>
    """
  end

  defp put_tap(node, tap), do: %{node | props: Map.put(node.props, :on_tap, tap)}

  @impl true
  def handle_info({:tap, {:switch_tab, tab}}, socket) do
    {:noreply, Mob.Socket.switch_tab(socket, tab)}
  end

  def handle_info({:tap, {:course, course_id}}, socket) do
    {:noreply,
     Mob.Socket.push_screen(socket, TcmMobile.Screens.CourseDetailScreen, %{course_id: course_id})}
  end

  def handle_info({:tap, {:category, category}}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:category, category)
     |> Mob.Socket.assign(:courses, load_courses(category, socket.assigns.query))}
  end

  def handle_info({:change, :search, query}, socket) do
    {:noreply,
     socket
     |> Mob.Socket.assign(:query, query)
     |> Mob.Socket.assign(:courses, load_courses(socket.assigns.category, query))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
end
