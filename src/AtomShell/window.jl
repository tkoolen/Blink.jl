using ..Blink
import Blink: js, id
import JSExpr: JSString, jsstring
import Base: position, size, close

export Window, flashframe, shell, progress, title,
  centre, floating, loadurl, opentools, closetools, tools,
  loadhtml, loadfile, css, front

mutable struct Window
  id::Int
  shell::Shell
  content
end

shell(win::Window) = win.shell
id(win::Window) = win.id

const window_defaults = @d(:url => "about:blank",
                           :title => "Julia",
                           "node-integration" => false,
                           "use-content-size" => true,
                           :icon => resolve_blink_asset("deps", "julia.png"))

raw_window(a::Electron, opts) = @js a createWindow($(merge(window_defaults, opts)))

function Window(a::Shell, opts::AbstractDict = Dict(); async=true)
  # TODO: Custom urls don't support async b/c don't load Blink.js. (Same as https://github.com/JunoLab/Blink.jl/issues/150)
  return haskey(opts, :url) ?
    Window(raw_window(a, opts), a, nothing) :
    Window(a, Page(), opts, async=async)
end

function Window(a::Shell, content::Page, opts::AbstractDict = Dict(); async=true)
  url = Blink.localurl(content)
  if !async
      # Send the callback id as a query param in the url.
      id, cond = Blink.callback!()
      url *= "?callback=$id"
  end
  # Create the window.
  opts = merge(opts, Dict(:url => url))
  w = Window(raw_window(a, opts), a, content)
  # If callback is requested, wait until the window has finished loading.
  if !async
      val = wait(cond)
      if isa(val, AbstractDict) && get(val, "type", "") == "error"
          err = JSError(get(val, "name", "unknown"), get(val, "message", "blank"))
          throw(err)
      end
  end
  return w
end

Window(args...; kwargs...) = Window(shell(), args...; kwargs...)

dot(a::Electron, win::Integer, code; callback = true) =
  js(a, :(withwin($(win), $(jsstring(code)...))),
     callback = callback)

dot(w::Window, code; callback = true) =
  ifelse(callback, dot(shell(w), id(w), code, callback = callback), w)

dot_(args...) = dot(args..., callback = false)

macro dot(win, code)
  :(dot($(esc(win)), $(Expr(:quote, Expr(:., :this, QuoteNode(code))))))
end

macro dot_(win, code)
  :(dot_($(esc(win)), $(Expr(:quote, Expr(:., :this, QuoteNode(code))))))
end

# Window management APIs

active(s::Electron, win::Integer) =
  @js s windows.hasOwnProperty($win)

active(win::Window) = active(shell(win), id(win))

flashframe(win::Window, on = true) =
  @dot_ win flashFrame($on)

progress(win::Window, p = -1) =
  @dot_ win setProgressBar($p)

title(win::Window, title) =
  @dot_ win setTitle($title)

title(win::Window) =
  @dot win getTitle()

centre(win::Window) =
  @dot_ win center()

position(win::Window, x, y) =
  @dot_ win setPosition($x, $y)

position(win::Window) =
  @dot win getPosition()

size(win::Window, w::Integer, h::Integer) =
  invoke(size, Tuple{Window, Any, Any}, win, w, h)

size(win::Window, w, h) =
  @dot_ win setSize($w, $h)

size(win::Window) =
  @dot win getSize()

floating(win::Window, flag) =
  @dot_ win setAlwaysOnTop($flag)

floating(win::Window) =
  @dot win isAlwaysOnTop()

loadurl(win::Window, url) =
  @dot win loadURL($url)

loadfile(win::Window, f) =
  loadurl(win, "file://$f")

opentools(win::Window) =
  @dot win openDevTools()

closetools(win::Window) =
  @dot win closeDevTools()

tools(win::Window) =
  @dot win toggleDevTools()

front(win::Window) =
  @dot win showInactive()

close(win::Window) =
  @dot win close()

# Window content APIs

active(::Nothing) = false

handlers(w::Window) = handlers(w.content)

msg(win::Window, m) = msg(win.content, m)

js(win::Window, s::JSString; callback = true) =
  active(win.content) ? js(win.content, s, callback = callback) :
    dot(win, :(this.webContents.executeJavaScript($(s.s))), callback = callback)

const initcss = """
  <style>html,body{margin:0;padding:0;border:0;text-align:center;}</style>
  """

function loadhtml(win::Window, html::AbstractString)
  tmp = string(tempname(), ".html")
  open(tmp, "w") do io
    println(io, initcss)
    println(io, html)
  end
  loadfile(win, tmp)
  @async (sleep(1); rm(tmp))
  return
end
