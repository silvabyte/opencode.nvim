local function hello()

	c
opencode.nvim initialized
OpenCode test environment loaded!
Commands:
  :OpenCodeStatus - Check server status
  :OpenCodeStart - Start server
  :OpenCodeStop - Stop server
Keymaps:
  <C-]> (insert mode) - Request completion
  <leader>oc - Toggle OpenCode
  <leader>os - Show status
[OpenCode] Starting OpenCode server {
  cmd = { "opencode", "serve", "--port=4096" }
}
[OpenCode] Starting OpenCode server on port 4096
OpenCode Server: Running (http://127.0.0.1:4096)
[OpenCode] Server started successfully
OpenCode Server: Running (http://127.0.0.1:4096)
2 fewer lines; before #1  0 seconds ago
"test.lua" [New] 2L, 24B written
[OpenCode] Requesting completion {
  file = "/home/matsilva/code/opencode.nvim/test.lua"
}
[OpenCode] HTTP request {
  method = "POST",
  path = "/api/sessions",
  url = "http://127.0.0.1:4096/api/sessions"
}
[OpenCode] Completion failed {
  error = 'Failed to create session: Failed to parse response: <!doctype html>\n<html lang="en">\n  <head>\n    <meta charset="utf-8" />\n    <meta name="viewport" content="wid
th=device-width, initial-scale=1" />\n    <meta name="theme-color" content="#000000" />\n    <link rel="shortcut icon" type="image/svg+xml" href="/favicon.svg" />\n    <title>O
penCode</title>\n    <script type="module" crossorigin src="/assets/index-DUxrKDWR.js"></script>\n    <link rel="stylesheet" crossorigin href="/assets/index-CixKim6D.css">\n  <
/head>\n  <body class="antialiased overscroll-none select-none text-12-regular">\n    <!-- <script> -->\n    <!--   ;(function () { -->\n    <!--     const savedTheme = localSt
orage.getItem("theme") || "opencode" -->\n    <!--     const savedDarkMode = localStorage.getItem("darkMode") !== "false" -->\n    <!--     document.documentElement.setAttribut
e("data-theme", savedTheme) -->\n    <!--     document.documentElement.setAttribute("data-dark", savedDarkMode.toString()) -->\n    <!--   })() -->\n    <!-- </script> -->\n
 <noscript>You need to enable JavaScript to run this app.</noscript>\n    <div id="root"></div>\n  </body>\n</html>\n'
}
[OpenCode] Request error {
  error = ""
}

