--[[
	COOLKID GUI V2  (モバイル対応 / 拡張しやすい黒×赤GUI)
	==========================================================
	構成
	  [1] GUI本体 (CK)       : 開閉 / ドラッグ / タブ / 部品 / 通知 / 確認 / 設定保存
	  [2] モジュール         : 機能ごとに分離 (CK.RegisterModule で登録)
	        - 外見(Appearance) / ユーティリティ / 設定
	  [3] 追加サンプル       : ファイル末尾のコメントを参照

	安全方針
	  ・他人への妨害 / 権限の不正取得 / 情報収集 / 外部コードの無条件実行は含みません
	  ・外見の変更は「自分の画面だけ」に反映されます (他のプレイヤーには見えません)
	  ・実装されていないボタンは「未実装」と表示し、動いたように見せません

	追加用API (getgenv().COOLKID_V2)
	  CK.RegisterModule(name, function(CK) ... end)     機能のまとまりを登録 (二重登録は拒否)
	  CK.UnloadModule(name)                             そのモジュールの部品/接続をすべて解除
	  CK.AddTab(name)                                   タブ追加 (同名は再利用)
	  tab:AddToggle / AddButton / AddDropdown / AddSlider / AddNumberInput /
	      AddTextInput / AddList / AddLabel / AddSection
	  CK.Notify(text, "success"|"error"|"warn"|"info")  通知
	  CK.Confirm{Title=, Message=, OnYes=, OnNo=}       確認ダイアログ
	  CK.SaveSettings() / CK.LoadSettings() / CK.ResetAll()
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local genv = (getgenv and getgenv()) or _G

-- 二重起動の防止 (古いGUIを完全に片付けてから起動)
if genv.COOLKID_V2 and genv.COOLKID_V2.Destroy then
	pcall(genv.COOLKID_V2.Destroy)
end

local CK = {
	Version = "2.0.0",
	Features = {},      -- id -> feature
	Modules = {},       -- name -> {cleanup=function, tabs={}}
	Settings = {ToastDuration = 3},
}
genv.COOLKID_V2 = CK

------------------------------------------------------------------
-- テーマ
------------------------------------------------------------------
local Theme = {
	BG = Color3.fromRGB(6, 6, 6),
	Panel = Color3.fromRGB(14, 14, 14),
	Accent = Color3.fromRGB(225, 25, 25),
	AccentD = Color3.fromRGB(80, 9, 9),
	Orange = Color3.fromRGB(255, 145, 30),
	Dim = Color3.fromRGB(190, 70, 50),
	Success = Color3.fromRGB(70, 225, 100),
	Error = Color3.fromRGB(255, 75, 75),
	Warn = Color3.fromRGB(255, 205, 50),
}
local FONT = Enum.Font.GothamBold
local FONT_TITLE = Enum.Font.GothamBlack

local GlobalConns = {}
local function Track(conn)
	table.insert(GlobalConns, conn)
	return conn
end

local Styled = {}
local function Style(inst, fn)
	table.insert(Styled, {inst = inst, fn = fn})
	fn()
end
local function RestyleAll()
	for i = #Styled, 1, -1 do
		local s = Styled[i]
		if not s.inst or not s.inst.Parent then
			table.remove(Styled, i)
		else
			pcall(s.fn)
		end
	end
end
local function SetAccent(color)
	Theme.Accent = color
	Theme.AccentD = Color3.new(color.R * 0.35, color.G * 0.35, color.B * 0.35)
	RestyleAll()
end

local function New(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then o.Parent = parent end
	return o
end

------------------------------------------------------------------
-- ScreenGui
------------------------------------------------------------------
local Gui = New("ScreenGui", {
	Name = "COOLKID_V2", ResetOnSpawn = false, DisplayOrder = 10000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true,
})
do
	local ok = pcall(function() Gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
	if not ok or not Gui.Parent then
		pcall(function() Gui.Parent = game:GetService("CoreGui") end)
	end
end

local WIN_W, WIN_H = 480, 340
local TITLE_H, TAB_H, STATUS_H = 42, 38, 28

------------------------------------------------------------------
-- 通知 (トースト)
------------------------------------------------------------------
local Toasts = New("Frame", {
	Name = "Toasts", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10),
	Size = UDim2.fromOffset(360, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, ZIndex = 200,
}, Gui)
New("UIListLayout", {Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder}, Toasts)
local ToastScale = New("UIScale", {Scale = 1}, Toasts)
local toastOrder = 0

function CK.Notify(text, kind, duration)
	kind = kind or "info"
	local color = (kind == "success" and Theme.Success) or (kind == "error" and Theme.Error)
		or (kind == "warn" and Theme.Warn) or Theme.Orange
	toastOrder += 1
	-- 同時表示は4件まで
	local kids = {}
	for _, c in ipairs(Toasts:GetChildren()) do
		if c:IsA("Frame") then table.insert(kids, c) end
	end
	if #kids >= 4 then kids[1]:Destroy() end

	local t = New("Frame", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.BG, BackgroundTransparency = 1, BorderSizePixel = 0,
		LayoutOrder = toastOrder, ZIndex = 200,
	}, Toasts)
	New("UICorner", {CornerRadius = UDim.new(0, 4)}, t)
	local st = New("UIStroke", {Color = color, Thickness = 2, Transparency = 1}, t)
	New("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, t)
	local lbl = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Text = tostring(text), TextWrapped = true, TextColor3 = color, Font = FONT, TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 1, ZIndex = 201,
	}, t)
	local ti = TweenInfo.new(0.2)
	TweenService:Create(t, ti, {BackgroundTransparency = 0.05}):Play()
	TweenService:Create(st, ti, {Transparency = 0}):Play()
	TweenService:Create(lbl, ti, {TextTransparency = 0}):Play()
	task.delay(duration or CK.Settings.ToastDuration, function()
		if not t.Parent then return end
		local to = TweenInfo.new(0.25)
		TweenService:Create(t, to, {BackgroundTransparency = 1}):Play()
		TweenService:Create(st, to, {Transparency = 1}):Play()
		TweenService:Create(lbl, to, {TextTransparency = 1}):Play()
		task.wait(0.28)
		if t.Parent then t:Destroy() end
	end)
end

------------------------------------------------------------------
-- ウィンドウ本体
------------------------------------------------------------------
local Win = New("CanvasGroup", {
	Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(WIN_W, WIN_H),
	BackgroundColor3 = Theme.BG, BorderSizePixel = 0, GroupTransparency = 0, Active = true,
}, Gui)
local WinScale = New("UIScale", {Scale = 1}, Win)
New("UICorner", {CornerRadius = UDim.new(0, 4)}, Win)
local WinStroke = New("UIStroke", {Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, Win)
Style(WinStroke, function() WinStroke.Color = Theme.Accent end)

local TitleBar = New("Frame", {
	Name = "TitleBar", Size = UDim2.new(1, 0, 0, TITLE_H), BackgroundColor3 = Theme.Panel,
	BorderSizePixel = 0, Active = true,
}, Win)
local TitleLine = New("Frame", {Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0}, TitleBar)
Style(TitleLine, function() TitleLine.BackgroundColor3 = Theme.Accent end)
New("TextLabel", {
	Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -110, 1, 0), BackgroundTransparency = 1,
	Text = "COOLKID GUI V2", TextColor3 = Theme.Orange, Font = FONT_TITLE, TextSize = 22,
	TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)

local function Flash(btn, restyle)
	if not btn.Parent then return end
	btn.BackgroundColor3 = Theme.Accent
	btn.TextColor3 = Color3.new(0, 0, 0)
	task.delay(0.14, function()
		if btn.Parent then pcall(restyle) end
	end)
end

local function StyleButton(btn, opts)
	opts = opts or {}
	local st = btn:FindFirstChildOfClass("UIStroke") or New("UIStroke", {Thickness = 1.8}, btn)
	local function apply()
		btn.BackgroundColor3 = opts.disabled and Color3.fromRGB(20, 20, 20) or Theme.BG
		btn.TextColor3 = opts.disabled and Theme.Dim or (opts.color or Theme.Orange)
		st.Color = opts.disabled and Theme.AccentD or Theme.Accent
	end
	Style(btn, apply)
	btn.AutoButtonColor = false
	-- 押した瞬間の反応
	btn.InputBegan:Connect(function(input)
		if opts.disabled then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			btn.BackgroundColor3 = Theme.AccentD
		end
	end)
	btn.InputEnded:Connect(function(input)
		if opts.disabled then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			apply()
		end
	end)
	return apply
end

local function TopButton(text, xFromRight)
	local b = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, xFromRight, 0.5, 0),
		Size = UDim2.fromOffset(44, 32), Text = text, Font = FONT, TextSize = 22, BorderSizePixel = 0,
		BackgroundColor3 = Theme.BG, TextColor3 = Theme.Orange,
	}, TitleBar)
	local restyle = StyleButton(b)
	return b, restyle
end
local MinBtn, MinRestyle = TopButton("−", -56)
local CloseBtn, CloseRestyle = TopButton("×", -8)

-- タブバー
local TabBar = New("ScrollingFrame", {
	Name = "Tabs", Position = UDim2.fromOffset(0, TITLE_H), Size = UDim2.new(1, 0, 0, TAB_H),
	BackgroundColor3 = Theme.BG, BorderSizePixel = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 0,
}, Win)
New("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder}, TabBar)
New("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, TabBar)

local Pages = New("Frame", {
	Name = "Pages", Position = UDim2.fromOffset(0, TITLE_H + TAB_H),
	Size = UDim2.new(1, 0, 1, -(TITLE_H + TAB_H + STATUS_H)), BackgroundTransparency = 1, ClipsDescendants = true,
}, Win)

-- ステータスバー
local StatusBar = New("Frame", {
	Position = UDim2.new(0, 0, 1, -STATUS_H), Size = UDim2.new(1, 0, 0, STATUS_H),
	BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
}, Win)
local StatusLine = New("Frame", {Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0}, StatusBar)
Style(StatusLine, function() StatusLine.BackgroundColor3 = Theme.Accent end)
local StatusLbl = New("TextLabel", {
	Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -130, 1, -2), BackgroundTransparency = 1,
	Text = "準備OK", TextColor3 = Theme.Orange, Font = FONT, TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, StatusBar)
local CountLbl = New("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 2), Size = UDim2.fromOffset(120, STATUS_H - 2),
	BackgroundTransparency = 1, Text = "", TextColor3 = Theme.Dim, Font = FONT, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
}, StatusBar)

function CK.SetStatus(text, kind)
	StatusLbl.Text = tostring(text)
	StatusLbl.TextColor3 = (kind == "success" and Theme.Success) or (kind == "error" and Theme.Error)
		or (kind == "warn" and Theme.Warn) or Theme.Orange
end
function CK.RefreshStatus()
	local total, on = 0, 0
	for _, f in pairs(CK.Features) do
		total += 1
		if f.Type == "toggle" and f:Get() then on += 1 end
	end
	CountLbl.Text = string.format("機能 %d / ON %d", total, on)
end

------------------------------------------------------------------
-- ドラッグ (タイトルバー / 丸型ボタン共通)
------------------------------------------------------------------
local function MakeDraggable(handle, getPos, setPos, onTap)
	local dragging, startInput, startPoint, startPos, moved = false, nil, nil, nil, false
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, moved, startInput = true, false, input
			startPoint = Vector2.new(input.Position.X, input.Position.Y)
			startPos = getPos()
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					c:Disconnect()
					if not moved and onTap then onTap() end
				end
			end)
		end
	end)
	Track(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input == startInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			local d = Vector2.new(input.Position.X, input.Position.Y) - startPoint
			if d.Magnitude > 8 then moved = true end
			if moved then setPos(startPos + d) end
		end
	end))
end

------------------------------------------------------------------
-- 位置 / スケール / 開閉アニメーション
------------------------------------------------------------------
local winCenter = Vector2.new(0, 0)
local bubblePos = Vector2.new(60, 130)
local respScale = 1
local isOpen = true
local animating = false

local function ViewSize()
	local v = Gui.AbsoluteSize
	if v.X < 10 then v = Workspace.CurrentCamera.ViewportSize end
	return v
end

local function ClampWin()
	local vp = ViewSize()
	local w, h = WIN_W * respScale, WIN_H * respScale
	local left = math.clamp(winCenter.X - w / 2, 110 - w, vp.X - 110)
	local top = math.clamp(winCenter.Y - h / 2, 0, vp.Y - 60)
	winCenter = Vector2.new(left + w / 2, top + h / 2)
end

local function PlaceWin()
	ClampWin()
	Win.Position = UDim2.fromOffset(winCenter.X, winCenter.Y)
end

local Bubble = New("Frame", {
	Name = "Bubble", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(66, 66),
	BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 150,
}, Gui)
New("UICorner", {CornerRadius = UDim.new(1, 0)}, Bubble)
Style(Bubble, function() Bubble.BackgroundColor3 = Theme.Accent end)
local BubbleScale = New("UIScale", {Scale = 1}, Bubble)
local BubbleInner = New("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -12, 1, -12),
	BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 151,
}, Bubble)
New("UICorner", {CornerRadius = UDim.new(1, 0)}, BubbleInner)
New("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "CK", TextColor3 = Theme.Orange,
	Font = FONT_TITLE, TextSize = 24, ZIndex = 152,
}, BubbleInner)

local function PlaceBubble()
	local vp = ViewSize()
	bubblePos = Vector2.new(math.clamp(bubblePos.X, 36, vp.X - 36), math.clamp(bubblePos.Y, 36, vp.Y - 36))
	Bubble.Position = UDim2.fromOffset(bubblePos.X, bubblePos.Y)
end

local function SetOpen(open)
	if animating or open == isOpen then return end
	animating = true
	isOpen = open
	local ti = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if open then
		Win.Visible = true
		Win.Position = UDim2.fromOffset(bubblePos.X, bubblePos.Y)
		WinScale.Scale = 0.05 * respScale
		Win.GroupTransparency = 1
		TweenService:Create(BubbleScale, TweenInfo.new(0.15), {Scale = 0}):Play()
		PlaceWin()
		TweenService:Create(Win, ti, {Position = UDim2.fromOffset(winCenter.X, winCenter.Y), GroupTransparency = 0}):Play()
		local t = TweenService:Create(WinScale, ti, {Scale = respScale})
		t.Completed:Connect(function() Bubble.Visible = false; animating = false end)
		t:Play()
	else
		ClampWin()
		PlaceBubble()
		Bubble.Visible = true
		BubbleScale.Scale = 0
		TweenService:Create(Win, ti, {Position = UDim2.fromOffset(bubblePos.X, bubblePos.Y), GroupTransparency = 1}):Play()
		TweenService:Create(BubbleScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
		local t = TweenService:Create(WinScale, ti, {Scale = 0.05 * respScale})
		t.Completed:Connect(function() Win.Visible = false; animating = false end)
		t:Play()
	end
end
CK.SetOpen = SetOpen

local function UpdateScale()
	local vp = ViewSize()
	respScale = math.clamp(math.min(vp.X * 0.96 / WIN_W, vp.Y * 0.92 / WIN_H), 0.55, 1.35)
	ToastScale.Scale = math.clamp(respScale, 0.8, 1.2)
	if isOpen and not animating then WinScale.Scale = respScale end
	PlaceWin()
	PlaceBubble()
end

MakeDraggable(TitleBar,
	function() return winCenter end,
	function(p) winCenter = p; PlaceWin() end)
MakeDraggable(Bubble,
	function() return bubblePos end,
	function(p) bubblePos = p; PlaceBubble() end,
	function() SetOpen(true) end)
MinBtn.Activated:Connect(function()
	Flash(MinBtn, MinRestyle)
	SetOpen(false)
end)

------------------------------------------------------------------
-- 確認ダイアログ
------------------------------------------------------------------
local ConfirmOverlay = nil
function CK.Confirm(opts)
	if ConfirmOverlay then ConfirmOverlay:Destroy() end
	local overlay = New("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35,
		BorderSizePixel = 0, Active = true, ZIndex = 60,
	}, Win)
	ConfirmOverlay = overlay
	local box = New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(340, 170),
		BackgroundColor3 = Theme.BG, BorderSizePixel = 0, ZIndex = 61,
	}, overlay)
	local st = New("UIStroke", {Thickness = 3}, box)
	Style(st, function() st.Color = Theme.Accent end)
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 30), BackgroundTransparency = 1,
		Text = opts.Title or "確認", TextColor3 = Theme.Orange, Font = FONT_TITLE, TextSize = 21,
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 62,
	}, box)
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 56), BackgroundTransparency = 1,
		Text = opts.Message or "", TextColor3 = Theme.Dim, Font = FONT, TextSize = 17, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 62,
	}, box)
	local function Close() if overlay.Parent then overlay:Destroy() end ConfirmOverlay = nil end
	local function Btn(text, x, cb)
		local b = New("TextButton", {
			Position = UDim2.new(x, x == 0 and 12 or 6, 1, -58), Size = UDim2.new(0.5, -18, 0, 46),
			Text = text, Font = FONT, TextSize = 19, BorderSizePixel = 0, BackgroundColor3 = Theme.BG, ZIndex = 62,
		}, box)
		local restyle = StyleButton(b)
		b.Activated:Connect(function()
			Flash(b, restyle)
			Close()
			if cb then
				local ok, err = pcall(cb)
				if not ok then CK.Notify("エラー: " .. tostring(err), "error") end
			end
		end)
	end
	Btn("はい", 0, opts.OnYes)
	Btn("いいえ", 0.5, opts.OnNo)
end

------------------------------------------------------------------
-- タブ / 機能 (部品) の基盤
------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab
local TabList, TabByName = {}, {}
local ActiveTab = nil
local CurrentModule = nil   -- RegisterModule 実行中のモジュール名

local function RestyleTab(tab)
	local sel = (ActiveTab == tab)
	tab.Button.BackgroundColor3 = sel and Theme.Accent or Theme.BG
	tab.Button.TextColor3 = sel and Color3.new(0, 0, 0) or Theme.Orange
	tab.ButtonStroke.Color = Theme.Accent
end

local function SelectTab(tab)
	ActiveTab = tab
	for _, t in ipairs(TabList) do
		t.Page.Visible = (t == tab)
		RestyleTab(t)
	end
end

function CK.AddTab(name)
	if TabByName[name] then return TabByName[name] end
	local tab = setmetatable({Name = name, Features = {}, NextOrder = 1, Module = CurrentModule}, Tab)
	tab.Button = New("TextButton", {
		Size = UDim2.new(0, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.X, Text = name, Font = FONT, TextSize = 17,
		BorderSizePixel = 0, BackgroundColor3 = Theme.BG, AutoButtonColor = false, LayoutOrder = #TabList + 1,
	}, TabBar)
	New("UIPadding", {PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14)}, tab.Button)
	tab.ButtonStroke = New("UIStroke", {Thickness = 1.8}, tab.Button)
	tab.Page = New("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Accent, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, Pages)
	New("UIListLayout", {Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder}, tab.Page)
	New("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 12)}, tab.Page)
	Style(tab.Page, function()
		tab.Page.ScrollBarImageColor3 = Theme.Accent
		RestyleTab(tab)
	end)
	tab.Button.Activated:Connect(function() SelectTab(tab) end)
	table.insert(TabList, tab)
	TabByName[name] = tab
	if not ActiveTab then SelectTab(tab) end
	return tab
end

local function DestroyTab(tab)
	for _, f in ipairs(table.clone(tab.Features)) do
		f:Destroy()
	end
	tab.Button:Destroy()
	tab.Page:Destroy()
	TabByName[tab.Name] = nil
	table.remove(TabList, table.find(TabList, tab))
	if ActiveTab == tab then
		ActiveTab = nil
		SelectTab(TabList[1])
	end
end

local function MakeRow(tab, height, auto)
	local row = New("Frame", {
		BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, LayoutOrder = tab.NextOrder,
		Size = UDim2.new(1, 0, 0, auto and 0 or height), AutomaticSize = auto and Enum.AutomaticSize.Y or Enum.AutomaticSize.None,
	}, tab.Page)
	tab.NextOrder += 1
	local st = New("UIStroke", {Thickness = 1.6}, row)
	Style(st, function() st.Color = Theme.Accent end)
	return row
end

local function NewFeature(tab, kind, opts)
	opts = opts or {}
	local id = opts.Id or (tab.Name .. ":" .. kind .. ":" .. tostring(opts.Name))
	if CK.Features[id] then
		CK.Notify("「" .. tostring(opts.Name or id) .. "」は既に登録されています (ID: " .. id .. ")", "warn")
		return nil, CK.Features[id]
	end
	local f = {
		Id = id, Name = opts.Name or id, Description = opts.Description or "", Type = kind, Tab = tab,
		Conns = {}, Persist = (opts.Persist ~= false), Module = CurrentModule, Destroyed = false,
	}
	CK.Features[id] = f
	table.insert(tab.Features, f)
	function f:Connect(signal, fn)
		local c = signal:Connect(fn)
		table.insert(self.Conns, c)
		return c
	end
	function f:Destroy()
		if self.Destroyed then return end
		self.Destroyed = true
		if self._onDestroy then
			local ok, err = pcall(self._onDestroy)
			if not ok then CK.Notify("後片付けでエラー (" .. self.Name .. "): " .. tostring(err), "error") end
		end
		for _, c in ipairs(self.Conns) do pcall(function() c:Disconnect() end) end
		if self.Row then self.Row:Destroy() end
		CK.Features[self.Id] = nil
		local i = table.find(tab.Features, self)
		if i then table.remove(tab.Features, i) end
		CK.RefreshStatus()
	end
	return f
end

local function SafeCall(f, fn, ...)
	if not fn then return true end
	local ok, err = pcall(fn, ...)
	if not ok then
		CK.Notify(f.Name .. " でエラー: " .. tostring(err), "error", 5)
		CK.SetStatus(f.Name .. ": エラー", "error")
	end
	return ok
end

local function NameDesc(row, f, rightPad)
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -(rightPad or 20), 0, 24), BackgroundTransparency = 1,
		Text = f.Name, TextColor3 = Theme.Orange, Font = FONT, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	if f.Description ~= "" then
		New("TextLabel", {
			Position = UDim2.fromOffset(12, 29), Size = UDim2.new(1, -(rightPad or 20), 0, 20), BackgroundTransparency = 1,
			Text = f.Description, TextColor3 = Theme.Dim, Font = FONT, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, row)
	end
end

------------------------------------------------------------------
-- 部品: セクション / ラベル
------------------------------------------------------------------
function Tab:AddSection(name)
	local lbl = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Text = "▌ " .. tostring(name), TextColor3 = Theme.Accent,
		Font = FONT_TITLE, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = self.NextOrder,
	}, self.Page)
	self.NextOrder += 1
	Style(lbl, function() lbl.TextColor3 = Theme.Accent end)
	return lbl
end

function Tab:AddLabel(opts)
	opts = type(opts) == "string" and {Text = opts} or opts
	local f, dup = NewFeature(self, "label", {Id = opts.Id, Name = opts.Text or "label", Persist = false})
	if not f then return dup end
	local row = MakeRow(self, 44, true)
	f.Row = row
	local lbl = New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Text = opts.Text or "",
		TextColor3 = Theme.Orange, Font = FONT, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	New("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10)}, row)
	function f:SetText(text, kind)
		lbl.Text = tostring(text)
		lbl.TextColor3 = (kind == "success" and Theme.Success) or (kind == "error" and Theme.Error)
			or (kind == "warn" and Theme.Warn) or Theme.Orange
	end
	function f:Get() return lbl.Text end
	return f
end

------------------------------------------------------------------
-- 部品: トグル (ON/OFF)
------------------------------------------------------------------
function Tab:AddToggle(opts)
	local f, dup = NewFeature(self, "toggle", opts)
	if not f then return dup end
	local row = MakeRow(self, f.Description ~= "" and 58 or 48)
	f.Row = row
	NameDesc(row, f, 96)
	local sw = New("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(64, 32),
		Text = "", BorderSizePixel = 0, AutoButtonColor = false,
	}, row)
	local swStroke = New("UIStroke", {Thickness = 1.8}, sw)
	local knob = New("Frame", {AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(24, 24), BorderSizePixel = 0}, sw)
	local onTxt = New("TextLabel", {BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Font = FONT, TextSize = 13, Text = "ON"}, sw)

	local state = false
	local default = opts.Default and true or false
	local function Visual()
		swStroke.Color = Theme.Accent
		if state then
			sw.BackgroundColor3 = Theme.Accent
			knob.BackgroundColor3 = Color3.new(0, 0, 0)
			knob.Position = UDim2.new(1, -28, 0.5, 0)
			onTxt.Position = UDim2.fromOffset(4, 0); onTxt.Text = "ON"; onTxt.TextColor3 = Color3.new(0, 0, 0)
		else
			sw.BackgroundColor3 = Theme.BG
			knob.BackgroundColor3 = Theme.Accent
			knob.Position = UDim2.fromOffset(4, 16)
			onTxt.Position = UDim2.new(1, -34, 0, 0); onTxt.Text = "OFF"; onTxt.TextColor3 = Theme.Dim
		end
	end
	Style(sw, Visual)

	local function Apply(newState, silent)
		if newState == state then return true end
		if not SafeCall(f, opts.Callback, newState) then
			Visual()
			return false
		end
		state = newState
		Visual()
		CK.RefreshStatus()
		if not silent then
			CK.SetStatus(f.Name .. ": " .. (state and "ON" or "OFF"), state and "success" or "info")
		end
		return true
	end
	function f:Get() return state end
	function f:Set(v, silent) return Apply(v and true or false, silent) end
	function f:Reset() Apply(default, true) end
	f._onDestroy = function()
		if state then SafeCall(f, opts.Callback, false) end
		if opts.Cleanup then opts.Cleanup() end
	end

	local last = 0
	f:Connect(sw.Activated, function()
		if os.clock() - last < 0.15 then return end   -- 連打対策
		last = os.clock()
		Apply(not state)
	end)
	if default then Apply(true, true) end
	CK.RefreshStatus()
	return f
end

------------------------------------------------------------------
-- 部品: ボタン
------------------------------------------------------------------
function Tab:AddButton(opts)
	local f, dup = NewFeature(self, "button", {Id = opts.Id, Name = opts.Name, Description = opts.Description, Persist = false})
	if not f then return dup end
	local implemented = type(opts.Callback) == "function"
	local row = MakeRow(self, f.Description ~= "" and 62 or 52)
	f.Row = row
	local btn = New("TextButton", {
		Position = UDim2.fromOffset(6, 5), Size = UDim2.new(1, -12, 1, -10), BorderSizePixel = 0,
		Text = implemented and f.Name or (f.Name .. "  (未実装)"), Font = FONT, TextSize = 18,
	}, row)
	local restyle = StyleButton(btn, {disabled = not implemented})
	if f.Description ~= "" then
		btn.Text = f.Name .. "\n" .. f.Description
		btn.RichText = false
		btn.TextSize = 16
		if not implemented then btn.Text = f.Name .. "  (未実装)\n" .. f.Description end
	end
	local busy = false
	local cooldown = opts.Cooldown or 0.35
	f:Connect(btn.Activated, function()
		if not implemented then
			CK.Notify("「" .. f.Name .. "」は未実装です", "warn")
			return
		end
		if busy then return end   -- 二重実行防止
		busy = true
		Flash(btn, restyle)
		local ok = SafeCall(f, opts.Callback)
		if ok then CK.SetStatus(f.Name .. ": 実行しました", "success") end
		task.delay(cooldown, function() busy = false end)
	end)
	function f:Get() return nil end
	function f:Set() end
	function f:Reset() end
	return f
end

------------------------------------------------------------------
-- 部品: ドロップダウン
------------------------------------------------------------------
function Tab:AddDropdown(opts)
	local f, dup = NewFeature(self, "dropdown", opts)
	if not f then return dup end
	local row = MakeRow(self, 50, true)
	f.Row = row
	New("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, row)
	local options = opts.Options or {}
	local value = opts.Default or options[1]
	local default = value
	local header = New("TextButton", {
		Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, LayoutOrder = 1,
	}, row)
	local nameLbl = New("TextLabel", {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.5, -12, 1, 0), BackgroundTransparency = 1, Text = f.Name,
		TextColor3 = Theme.Orange, Font = FONT, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, header)
	local valLbl = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.5, -12, 1, 0), BackgroundTransparency = 1,
		Text = tostring(value) .. " ▼", TextColor3 = Theme.Accent, Font = FONT, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Right,
	}, header)
	Style(valLbl, function() valLbl.TextColor3 = Theme.Accent end)
	local list = New("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false, LayoutOrder = 2,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
	}, row)
	New("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, list)
	New("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)}, list)

	local function SetValue(v, silent)
		if v == value then return true end
		if not SafeCall(f, opts.Callback, v) then return false end
		value = v
		valLbl.Text = tostring(v) .. (list.Visible and " ▲" or " ▼")
		if not silent then CK.SetStatus(f.Name .. ": " .. tostring(v), "success") end
		return true
	end
	local function Close()
		list.Visible = false
		valLbl.Text = tostring(value) .. " ▼"
	end
	local function Build()
		for _, c in ipairs(list:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		for i, opt in ipairs(options) do
			local b = New("TextButton", {Size = UDim2.new(1, 0, 0, 42), Text = tostring(opt), Font = FONT, TextSize = 17, BorderSizePixel = 0, LayoutOrder = i}, list)
			local restyle = StyleButton(b)
			b.Activated:Connect(function()
				Flash(b, restyle)
				SetValue(opt)
				Close()
			end)
		end
		list.Size = UDim2.new(1, 0, 0, math.min(#options * 46 + 8, 190))
	end
	Build()
	f:Connect(header.Activated, function()
		list.Visible = not list.Visible
		valLbl.Text = tostring(value) .. (list.Visible and " ▲" or " ▼")
	end)
	function f:Get() return value end
	function f:Set(v, silent) if table.find(options, v) then return SetValue(v, silent) end CK.Notify("無効な選択肢: " .. tostring(v), "error") return false end
	function f:Reset() SetValue(default, true) end
	function f:SetOptions(newOptions)
		options = newOptions
		if not table.find(options, value) then value = options[1]; valLbl.Text = tostring(value) .. " ▼" end
		Build()
	end
	if default ~= nil and opts.Callback then SafeCall(f, opts.Callback, default) end
	return f
end

------------------------------------------------------------------
-- 部品: スライダー
------------------------------------------------------------------
function Tab:AddSlider(opts)
	local f, dup = NewFeature(self, "slider", opts)
	if not f then return dup end
	local row = MakeRow(self, 70)
	f.Row = row
	local min, max, step = opts.Min or 0, opts.Max or 100, opts.Step or 1
	if max <= min then CK.Notify("スライダー設定が不正です: " .. f.Name, "error"); f:Destroy(); return nil end
	local default = math.clamp(opts.Default or min, min, max)
	local value = default
	local suffix = opts.Suffix or ""
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 5), Size = UDim2.new(0.6, -12, 0, 26), BackgroundTransparency = 1, Text = f.Name,
		TextColor3 = Theme.Orange, Font = FONT, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	local valLbl = New("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 5), Size = UDim2.new(0.4, -12, 0, 26), BackgroundTransparency = 1,
		Text = "", TextColor3 = Theme.Accent, Font = FONT, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right,
	}, row)
	Style(valLbl, function() valLbl.TextColor3 = Theme.Accent end)
	local track = New("Frame", {
		Position = UDim2.new(0, 14, 0, 44), Size = UDim2.new(1, -28, 0, 14), BackgroundColor3 = Theme.BG, BorderSizePixel = 0, Active = true,
	}, row)
	local tStroke = New("UIStroke", {Thickness = 1.5}, track)
	local fill = New("Frame", {Size = UDim2.fromScale(0, 1), BorderSizePixel = 0}, track)
	local knob = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), Position = UDim2.fromScale(0, 0.5), BorderSizePixel = 0}, track)
	New("UICorner", {CornerRadius = UDim.new(1, 0)}, knob)
	Style(track, function()
		tStroke.Color = Theme.Accent; fill.BackgroundColor3 = Theme.Accent; knob.BackgroundColor3 = Theme.Orange
	end)

	local function Visual()
		local a = (value - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, 0.5)
		local shown = (step < 1) and string.format("%.2f", value) or tostring(value)
		valLbl.Text = shown .. suffix
	end
	local function SetValue(v, silent)
		v = math.clamp(math.floor((v - min) / step + 0.5) * step + min, min, max)
		if v == value then return true end
		if not SafeCall(f, opts.Callback, v) then return false end
		value = v
		Visual()
		if not silent then CK.SetStatus(f.Name .. ": " .. valLbl.Text, "info") end
		return true
	end
	Visual()

	local dragging, dragInput = false, nil
	local function FromInput(input)
		local a = math.clamp((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		SetValue(min + (max - min) * a, true)
	end
	f:Connect(track.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging, dragInput = true, input
			self.Page.ScrollingEnabled = false     -- ドラッグ中は画面スクロールを止める
			FromInput(input)
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					self.Page.ScrollingEnabled = true
					CK.SetStatus(f.Name .. ": " .. valLbl.Text, "info")
					c:Disconnect()
				end
			end)
		end
	end)
	f:Connect(UserInputService.InputChanged, function(input)
		if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.MouseMovement) then
			FromInput(input)
		end
	end)
	function f:Get() return value end
	function f:Set(v, silent)
		if type(v) ~= "number" then CK.Notify("数値ではありません: " .. tostring(v), "error"); return false end
		return SetValue(v, silent)
	end
	function f:Reset() SetValue(default, true) end
	f._onDestroy = function()
		self.Page.ScrollingEnabled = true
		if opts.Cleanup then opts.Cleanup() end
	end
	if opts.Callback and opts.ApplyDefault ~= false then SafeCall(f, opts.Callback, value) end
	return f
end

------------------------------------------------------------------
-- 部品: 数値入力 / テキスト入力
------------------------------------------------------------------
local function InputRow(tab, f, placeholder, initial)
	local row = MakeRow(tab, 56)
	f.Row = row
	New("TextLabel", {
		Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.45, -12, 1, 0), BackgroundTransparency = 1, Text = f.Name,
		TextColor3 = Theme.Orange, Font = FONT, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, row)
	local box = New("TextBox", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.55, -14, 0, 40),
		BackgroundColor3 = Theme.BG, BorderSizePixel = 0, Text = initial, PlaceholderText = placeholder, Font = FONT, TextSize = 18,
		TextColor3 = Theme.Orange, PlaceholderColor3 = Theme.Dim, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
	}, row)
	New("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, box)
	local st = New("UIStroke", {Thickness = 1.8}, box)
	Style(box, function() st.Color = Theme.Accent end)
	return box
end

function Tab:AddNumberInput(opts)
	local f, dup = NewFeature(self, "number", opts)
	if not f then return dup end
	local min, max = opts.Min or -math.huge, opts.Max or math.huge
	local default = opts.Default or 0
	local value = default
	local box = InputRow(self, f, "数値", tostring(value))
	pcall(function() box.TextInputType = Enum.TextInputType.Number end)
	local function SetValue(n, silent)
		if n == value then return true end
		if not SafeCall(f, opts.Callback, n) then return false end
		value = n
		box.Text = tostring(n)
		if not silent then CK.SetStatus(f.Name .. ": " .. tostring(n), "success") end
		return true
	end
	f:Connect(box.FocusLost, function()
		local n = tonumber(box.Text)
		if not n or n < min or n > max or (opts.Integer and n % 1 ~= 0) then
			CK.Notify(f.Name .. ": " .. tostring(min) .. " ~ " .. tostring(max) .. " の" .. (opts.Integer and "整数" or "数値") .. "を入力してください", "error")
			box.Text = tostring(value)
			return
		end
		SetValue(n)
	end)
	function f:Get() return value end
	function f:Set(v, silent)
		if type(v) ~= "number" or v < min or v > max then CK.Notify("無効な数値: " .. tostring(v), "error"); return false end
		return SetValue(v, silent)
	end
	function f:Reset() SetValue(default, true) end
	if opts.Callback and opts.ApplyDefault ~= false then SafeCall(f, opts.Callback, value) end
	return f
end

function Tab:AddTextInput(opts)
	local f, dup = NewFeature(self, "text", opts)
	if not f then return dup end
	local default = opts.Default or ""
	local value = default
	local box = InputRow(self, f, opts.Placeholder or "入力…", value)
	local function SetValue(text, silent)
		if opts.Validate then
			local ok, res, msg = pcall(opts.Validate, text)
			if not ok or res == false then
				CK.Notify(f.Name .. ": " .. tostring((ok and msg) or res or "入力が不正です"), "error")
				box.Text = value
				return false
			end
		end
		if not SafeCall(f, opts.Callback, text) then return false end
		value = text
		box.Text = text
		if not silent then CK.SetStatus(f.Name .. ": 更新しました", "success") end
		return true
	end
	f:Connect(box.FocusLost, function() SetValue(box.Text) end)
	function f:Get() return value end
	function f:Set(v, silent) return SetValue(tostring(v), silent) end
	function f:Reset() SetValue(default, true) end
	if opts.Callback and opts.ApplyDefault ~= false then SafeCall(f, opts.Callback, value) end
	return f
end

------------------------------------------------------------------
-- 部品: 検索付きスクロールリスト
------------------------------------------------------------------
function Tab:AddList(opts)
	local f, dup = NewFeature(self, "list", {Id = opts.Id, Name = opts.Name, Persist = false})
	if not f then return dup end
	local row = MakeRow(self, 50, true)
	f.Row = row
	New("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, row)
	New("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, row)
	New("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = f.Name, TextColor3 = Theme.Orange, Font = FONT, TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1,
	}, row)
	local search
	if opts.Searchable ~= false then
		search = New("TextBox", {
			Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.BG, BorderSizePixel = 0, Text = "", PlaceholderText = "🔍 検索",
			Font = FONT, TextSize = 17, TextColor3 = Theme.Orange, PlaceholderColor3 = Theme.Dim, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2,
		}, row)
		New("UIPadding", {PaddingLeft = UDim.new(0, 10)}, search)
		local st = New("UIStroke", {Thickness = 1.8}, search)
		Style(search, function() st.Color = Theme.Accent end)
	end
	local scroll = New("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, opts.Height or 170), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
	}, row)
	New("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, scroll)
	local items = opts.Items or {}
	local function Build()
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local q = search and string.lower(search.Text) or ""
		local shown = 0
		for i, it in ipairs(items) do
			local nm = tostring(it.Name or it)
			if q == "" or string.find(string.lower(nm), q, 1, true) then
				shown += 1
				local b = New("TextButton", {Size = UDim2.new(1, -6, 0, 40), Text = nm, Font = FONT, TextSize = 16, BorderSizePixel = 0, LayoutOrder = i, TextTruncate = Enum.TextTruncate.AtEnd}, scroll)
				local restyle = StyleButton(b)
				b.Activated:Connect(function()
					Flash(b, restyle)
					SafeCall(f, opts.Callback, it)
				end)
			end
		end
		if shown == 0 then
			New("TextLabel", {Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Text = "見つかりません", TextColor3 = Theme.Dim, Font = FONT, TextSize = 16}, scroll)
		end
	end
	if search then f:Connect(search:GetPropertyChangedSignal("Text"), Build) end
	function f:SetItems(newItems) items = newItems; Build() end
	function f:Get() return items end
	function f:Set() end
	function f:Reset() end
	Build()
	return f
end

------------------------------------------------------------------
-- 設定の保存 / 読み込み / 初期化
------------------------------------------------------------------
local SETTINGS_FILE = "COOLKID_V2_settings.json"
function CK.FileSupport()
	return typeof(writefile) == "function" and typeof(readfile) == "function" and typeof(isfile) == "function"
end

function CK.SaveSettings()
	if not CK.FileSupport() then
		CK.Notify("この環境はファイル保存に対応していないため、保存できません", "warn", 4)
		return false
	end
	local values, n = {}, 0
	for id, f in pairs(CK.Features) do
		if f.Persist and f.Type ~= "button" and f.Type ~= "label" and f.Type ~= "list" then
			values[id] = f:Get()
			n += 1
		end
	end
	local ok, err = pcall(function()
		writefile(SETTINGS_FILE, HttpService:JSONEncode({version = 2, accent = {Theme.Accent.R, Theme.Accent.G, Theme.Accent.B}, values = values}))
	end)
	if ok then CK.Notify("設定を保存しました (" .. n .. "件)", "success") else CK.Notify("保存に失敗: " .. tostring(err), "error", 5) end
	return ok
end

function CK.LoadSettings()
	if not CK.FileSupport() then
		CK.Notify("この環境はファイル読み込みに対応していません", "warn", 4)
		return false
	end
	local okExists, exists = pcall(isfile, SETTINGS_FILE)
	if not okExists or not exists then
		CK.Notify("保存された設定がありません", "warn")
		return false
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(readfile(SETTINGS_FILE)) end)
	if not ok or type(data) ~= "table" or type(data.values) ~= "table" then
		CK.Notify("設定ファイルが壊れています。「初期化」してから保存し直してください", "error", 5)
		return false
	end
	local n, skipped = 0, 0
	for id, v in pairs(data.values) do
		local f = CK.Features[id]
		if f then
			if f:Set(v, true) ~= false then n += 1 else skipped += 1 end
		else
			skipped += 1
		end
	end
	CK.Notify("設定を読み込みました (" .. n .. "件" .. (skipped > 0 and (" / 未適用 " .. skipped .. "件") or "") .. ")", "success")
	return true
end

function CK.ResetAll()
	for _, f in pairs(table.clone(CK.Features)) do
		if f.Reset then pcall(function() f:Reset() end) end
	end
	CK.RefreshStatus()
	CK.Notify("すべての設定を初期値に戻しました", "success")
end

------------------------------------------------------------------
-- モジュール管理
------------------------------------------------------------------
function CK.RegisterModule(name, fn)
	if CK.Modules[name] then
		CK.Notify("モジュール「" .. name .. "」は既に読み込まれています", "warn")
		return false
	end
	CK.Modules[name] = {tabs = {}}
	CurrentModule = name
	local ok, res = pcall(fn, CK)
	CurrentModule = nil
	if not ok then
		CK.Notify("モジュール「" .. name .. "」の読み込みに失敗: " .. tostring(res), "error", 6)
		CK.UnloadModule(name)
		return false
	end
	if type(res) == "function" then CK.Modules[name].cleanup = res end
	return true
end

function CK.UnloadModule(name)
	local m = CK.Modules[name]
	if not m then return false end
	for id, f in pairs(table.clone(CK.Features)) do
		if f.Module == name then f:Destroy() end
	end
	if m.cleanup then
		local ok, err = pcall(m.cleanup)
		if not ok then CK.Notify("後片付けでエラー (" .. name .. "): " .. tostring(err), "error") end
	end
	for _, tab in ipairs(table.clone(TabList)) do
		if tab.Module == name then DestroyTab(tab) end
	end
	CK.Modules[name] = nil
	CK.RefreshStatus()
	return true
end

function CK.Destroy()
	for name in pairs(table.clone(CK.Modules)) do
		CK.UnloadModule(name)
	end
	for _, f in pairs(table.clone(CK.Features)) do pcall(function() f:Destroy() end) end
	for _, c in ipairs(GlobalConns) do pcall(function() c:Disconnect() end) end
	GlobalConns = {}
	pcall(function() Gui:Destroy() end)
	if genv.COOLKID_V2 == CK then genv.COOLKID_V2 = nil end
end

CloseBtn.Activated:Connect(function()
	Flash(CloseBtn, CloseRestyle)
	CK.Confirm({
		Title = "COOLKID GUI V2 を終了",
		Message = "GUIを閉じます。外見の変更などは元に戻します。よろしいですか？",
		OnYes = function() CK.Destroy() end,
	})
end)

Track(Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateScale))

------------------------------------------------------------------
-- ================ ここからモジュール (機能) ================
-- GUI本体には手を入れず、機能はすべて RegisterModule の中に書きます
------------------------------------------------------------------

------------------------------------------------------------------
-- モジュール1: 外見 (Appearance)
-- すべて「自分の画面だけ」の変更です。他の人には見えません
------------------------------------------------------------------
CK.RegisterModule("Appearance", function(CK)
	local tab = CK.AddTab("外見")
	local RED = Color3.fromRGB(225, 25, 25)
	local AP = {applied = false, backup = nil, auto = true, line1 = "teamCoolkidd", line2 = "join today!", labels = {}}

	local function Log(statusLbl, text, kind)
		if statusLbl then statusLbl:SetText(text, kind) end
	end

	local function Reset(silent)
		local b = AP.backup
		if not b then return end
		for _, a in ipairs(b.accessories) do
			if a.inst and not a.inst.Parent then pcall(function() a.inst.Parent = a.parent end) end
		end
		if b.bodyColors then
			pcall(function()
				if b.createdBC then
					b.bodyColors.inst:Destroy()
				else
					for k, v in pairs(b.bodyColors.colors) do b.bodyColors.inst[k] = v end
				end
			end)
		end
		for _, c in ipairs(b.clothes) do
			pcall(function()
				if c.kind == "color" then c.inst.Color3 = c.color else c.inst.Parent = c.parent end
			end)
		end
		if b.faceDecal then pcall(function() b.faceDecal.inst.Transparency = b.faceDecal.transparency end) end
		for _, g in ipairs(b.guis) do pcall(function() g:Destroy() end) end
		AP.labels = {}
		AP.backup = nil
		AP.applied = false
		if not silent then CK.Notify("外見を元に戻しました", "success") end
	end

	local function Apply(status)
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local head = char and char:FindFirstChild("Head")
		if not (char and hum and head) then
			CK.Notify("キャラクターが見つかりません。読み込み後にもう一度押してください", "error")
			return false
		end
		if AP.applied then Reset(true) end
		local b = {accessories = {}, clothes = {}, guis = {}}
		AP.backup = b
		local report, fails = {}, {}

		-- 1) 頭のアクセサリー(髪・帽子・顔)を外す
		local removed = 0
		for _, a in ipairs(char:GetChildren()) do
			if a:IsA("Accessory") then
				local okT, t = pcall(function() return a.AccessoryType end)
				if not okT or t == Enum.AccessoryType.Hat or t == Enum.AccessoryType.Hair or t == Enum.AccessoryType.Face
					or t == Enum.AccessoryType.Unknown then
					table.insert(b.accessories, {inst = a, parent = a.Parent})
					a.Parent = nil
					removed += 1
				end
			end
		end
		table.insert(report, "アクセサリー " .. removed .. "個を外しました")

		-- 2) 体の色を赤に (BodyColors)
		local okBC, errBC = pcall(function()
			local bc = char:FindFirstChildOfClass("BodyColors")
			local created = false
			if not bc then
				bc = Instance.new("BodyColors")
				bc.Parent = char
				created = true
			end
			b.createdBC = created
			b.bodyColors = {inst = bc, colors = {
				HeadColor3 = bc.HeadColor3, TorsoColor3 = bc.TorsoColor3, LeftArmColor3 = bc.LeftArmColor3,
				RightArmColor3 = bc.RightArmColor3, LeftLegColor3 = bc.LeftLegColor3, RightLegColor3 = bc.RightLegColor3,
			}}
			for k in pairs(b.bodyColors.colors) do bc[k] = RED end
		end)
		if okBC then table.insert(report, "顔・腕・脚・胴体を赤にしました") else table.insert(fails, "体の色: " .. tostring(errBC)) end

		-- 3) シャツ・ズボンを赤に (テクスチャは変えられないので色を乗せる)
		local clothesCount = 0
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Shirt") or c:IsA("Pants") then
				table.insert(b.clothes, {kind = "color", inst = c, color = c.Color3})
				c.Color3 = RED
				clothesCount += 1
			elseif c:IsA("ShirtGraphic") then
				table.insert(b.clothes, {kind = "parent", inst = c, parent = c.Parent})
				c.Parent = nil
			end
		end
		if clothesCount > 0 then
			table.insert(report, "シャツ/ズボン " .. clothesCount .. "点を赤に着色しました")
		else
			table.insert(report, "シャツ/ズボンが無いので体の色で表現しました")
		end

		-- 4) 顔: 元の顔を隠し、"^-^" の笑顔を表示
		local okF, errF = pcall(function()
			local decal = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal")
			if decal then
				b.faceDecal = {inst = decal, transparency = decal.Transparency}
				decal.Transparency = 1
			end
			local sg = Instance.new("SurfaceGui")
			sg.Name = "CK_Face"; sg.Face = Enum.NormalId.Front; sg.Adornee = head
			sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; sg.CanvasSize = Vector2.new(200, 200)
			sg.LightInfluence = 0; sg.Parent = head
			New("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "^-^", TextColor3 = Color3.new(0, 0, 0),
				Font = Enum.Font.GothamBlack, TextScaled = true,
			}, sg)
			table.insert(b.guis, sg)
		end)
		if okF then
			table.insert(report, "顔を ^-^ にしました (文字で表現・自分の画面のみ)")
		else
			table.insert(fails, "顔: " .. tostring(errF))
		end

		-- 5) 胴体の中央に文字
		local okT2, errT2 = pcall(function()
			local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
			if not torso then error("胴体パーツが見つかりません") end
			local canvas = (torso.Name == "UpperTorso") and Vector2.new(260, 208) or Vector2.new(260, 260)
			local sg = Instance.new("SurfaceGui")
			sg.Name = "CK_Shirt"; sg.Face = Enum.NormalId.Front; sg.Adornee = torso
			sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; sg.CanvasSize = canvas
			sg.LightInfluence = 0; sg.Parent = torso
			local function Line(text, y, h)
				return New("TextLabel", {
					Position = UDim2.fromScale(0, y), Size = UDim2.fromScale(1, h), BackgroundTransparency = 1, Text = text,
					TextColor3 = Color3.new(1, 1, 1), TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.25,
					Font = Enum.Font.GothamBlack, TextScaled = true,
				}, sg)
			end
			AP.labels = {Line(AP.line1, 0.20, 0.30), Line(AP.line2, 0.52, 0.26)}
			table.insert(b.guis, sg)
		end)
		if okT2 then table.insert(report, "胴体に文字を表示しました") else table.insert(fails, "胴体の文字: " .. tostring(errT2)) end

		AP.applied = true
		Log(status, table.concat(report, " / "), "success")
		CK.Notify("外見を適用しました (あなたの画面だけに反映されます)", "success", 4)
		for _, m in ipairs(fails) do CK.Notify("変更できませんでした: " .. m, "error", 6) end
		return true
	end

	tab:AddSection("キャラクターの外見")
	local status = tab:AddLabel({Id = "ap_status", Text = "未適用です。「適用」を押してください"})
	tab:AddTextInput({
		Id = "ap_line1", Name = "胴体の文字 1行目", Default = AP.line1, Placeholder = "teamCoolkidd",
		Validate = function(t) if #t == 0 or #t > 24 then return false, "1〜24文字で入力してください" end return true end,
		Callback = function(t) AP.line1 = t; if AP.labels[1] then AP.labels[1].Text = t end end,
	})
	tab:AddTextInput({
		Id = "ap_line2", Name = "胴体の文字 2行目", Default = AP.line2, Placeholder = "join today!",
		Validate = function(t) if #t == 0 or #t > 24 then return false, "1〜24文字で入力してください" end return true end,
		Callback = function(t) AP.line2 = t; if AP.labels[2] then AP.labels[2].Text = t end end,
	})
	tab:AddButton({Id = "ap_apply", Name = "外見を適用", Description = "髪を外す・赤色・^-^・胴体の文字", Callback = function() Apply(status) end})
	tab:AddButton({Id = "ap_reset", Name = "元に戻す", Description = "適用前の外見に戻します", Callback = function()
		if AP.applied then Reset(false); Log(status, "元に戻しました", "info") else CK.Notify("適用していないので戻す内容がありません", "warn") end
	end})
	tab:AddToggle({
		Id = "ap_auto", Name = "リスポーン後に自動で再適用", Description = "死亡/リセット後にも同じ外見にします", Default = true,
		Callback = function(on) AP.auto = on end,
	})

	-- リスポーン対応
	local lastWasApplied = false
	local c1 = LocalPlayer.CharacterAdded:Connect(function(char)
		AP.backup, AP.applied, AP.labels = nil, false, {}   -- 古いキャラの記録は無効
		if AP.auto and lastWasApplied then
			task.spawn(function()
				local hum = char:WaitForChild("Humanoid", 10)
				local head = char:WaitForChild("Head", 10)
				if hum and head and LocalPlayer.Character == char then
					task.wait(1)   -- 見た目の読み込み待ち
					Apply(status)
				else
					CK.Notify("リスポーン後の再適用に失敗しました (キャラ読み込み待ち)", "error")
				end
			end)
		end
	end)
	local c2 = LocalPlayer.CharacterRemoving:Connect(function() lastWasApplied = AP.applied end)

	return function()   -- モジュール解除時の後片付け
		c1:Disconnect(); c2:Disconnect()
		Reset(true)
	end
end)

------------------------------------------------------------------
-- モジュール2: ユーティリティ (実際に動く見た目/表示系の機能)
------------------------------------------------------------------
CK.RegisterModule("Utility", function(CK)
	local tab = CK.AddTab("機能")
	local cam = function() return Workspace.CurrentCamera end

	tab:AddSection("表示")
	-- FPSカウンター
	local fpsLabel, fpsConn
	tab:AddToggle({
		Id = "fps", Name = "FPS表示", Description = "画面の右上にFPSを表示",
		Callback = function(on)
			if on then
				fpsLabel = New("TextLabel", {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 60), Size = UDim2.fromOffset(110, 28),
					BackgroundColor3 = Theme.BG, BackgroundTransparency = 0.2, TextColor3 = Theme.Orange, Font = FONT, TextSize = 17,
					Text = "FPS --", ZIndex = 90,
				}, Gui)
				local st = New("UIStroke", {Color = Theme.Accent, Thickness = 2}, fpsLabel)
				local acc, n = 0, 0
				fpsConn = RunService.RenderStepped:Connect(function(dt)
					acc += dt; n += 1
					if acc >= 0.5 then fpsLabel.Text = "FPS " .. math.floor(n / acc + 0.5); acc, n = 0, 0 end
				end)
			else
				if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
				if fpsLabel then fpsLabel:Destroy(); fpsLabel = nil end
			end
		end,
		Cleanup = function()
			if fpsConn then fpsConn:Disconnect() end
			if fpsLabel then fpsLabel:Destroy() end
		end,
	})

	-- 視野角(FOV)
	local origFov = cam() and cam().FieldOfView or 70
	tab:AddSlider({
		Id = "fov", Name = "視野角 (FOV)", Min = 40, Max = 120, Step = 1, Default = math.floor(origFov + 0.5), Suffix = "°",
		ApplyDefault = false,
		Callback = function(v) cam().FieldOfView = v end,
		Cleanup = function() if cam() then cam().FieldOfView = origFov end end,
	})

	-- 時刻 (自分の画面のみ)
	local origClock = Lighting.ClockTime
	tab:AddSlider({
		Id = "clock", Name = "時刻 (自分の画面のみ)", Min = 0, Max = 24, Step = 0.5, Default = origClock, Suffix = "h",
		ApplyDefault = false,
		Callback = function(v) Lighting.ClockTime = v end,
		Cleanup = function() Lighting.ClockTime = origClock end,
	})

	-- ウォーターマーク
	local wm
	tab:AddTextInput({
		Id = "watermark", Name = "ウォーターマーク", Default = "", Placeholder = "画面左下に表示する文字",
		Validate = function(t) if #t > 30 then return false, "30文字以内にしてください" end return true end,
		Callback = function(t)
			if t == "" then
				if wm then wm:Destroy(); wm = nil end
				return
			end
			if not wm then
				wm = New("TextLabel", {
					AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(0, 24),
					AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Theme.BG, BackgroundTransparency = 0.25,
					TextColor3 = Theme.Orange, Font = FONT, TextSize = 16, ZIndex = 80,
				}, Gui)
				New("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, wm)
			end
			wm.Text = t
		end,
		ApplyDefault = false,
	})

	tab:AddSection("GUI設定")
	tab:AddDropdown({
		Id = "theme", Name = "テーマカラー", Options = {"赤", "オレンジ", "ピンク", "白"}, Default = "赤",
		Callback = function(v)
			local map = {["赤"] = Color3.fromRGB(225, 25, 25), ["オレンジ"] = Color3.fromRGB(255, 120, 20),
				["ピンク"] = Color3.fromRGB(255, 60, 140), ["白"] = Color3.fromRGB(235, 235, 235)}
			if not map[v] then error("未対応の色: " .. tostring(v)) end
			SetAccent(map[v])
		end,
	})
	tab:AddNumberInput({
		Id = "toast_sec", Name = "通知の表示秒数", Min = 1, Max = 10, Default = 3, Integer = true,
		Callback = function(n) CK.Settings.ToastDuration = n end,
	})
	tab:AddButton({Id = "test_ok", Name = "通知テスト (成功)", Callback = function() CK.Notify("成功の通知です", "success") end})
	tab:AddButton({Id = "test_err", Name = "通知テスト (失敗)", Callback = function() CK.Notify("失敗の通知です", "error") end})
	tab:AddButton({Id = "todo", Name = "未実装ボタンの例", Description = "Callbackが無いボタンはこう表示されます"})

	-- 機能一覧 (検索 + スクロールリスト)
	local listFeature
	local function Items()
		local items = {}
		for id, f in pairs(CK.Features) do
			if f.Type ~= "label" and f.Type ~= "list" then
				table.insert(items, {Name = f.Name .. "  [" .. f.Type .. "]", Feature = f})
			end
		end
		table.sort(items, function(a, b) return a.Name < b.Name end)
		return items
	end
	listFeature = tab:AddList({
		Id = "feature_list", Name = "機能一覧 (検索できます)", Items = Items(), Height = 160,
		Callback = function(item)
			local f = item.Feature
			local st = (f.Type == "toggle") and (f:Get() and "ON" or "OFF") or tostring(f:Get())
			CK.SetStatus(f.Name .. " / " .. (f.Description ~= "" and f.Description or f.Id) .. " / 状態: " .. st, "info")
		end,
	})
	tab:AddButton({Id = "list_refresh", Name = "一覧を更新", Callback = function() listFeature:SetItems(Items()) end})
end)

------------------------------------------------------------------
-- モジュール3: 設定 (保存 / 読み込み / 初期化)
------------------------------------------------------------------
CK.RegisterModule("Settings", function(CK)
	local tab = CK.AddTab("設定")
	tab:AddSection("設定の保存")
	tab:AddLabel({Id = "env_info", Text = CK.FileSupport() and "ファイル保存: 対応しています" or "ファイル保存: この環境は未対応です (保存/読み込みは使えません)"})
	tab:AddButton({Id = "save", Name = "設定を保存", Callback = function() CK.SaveSettings() end})
	tab:AddButton({Id = "load", Name = "設定を読み込み", Callback = function() CK.LoadSettings() end})
	tab:AddButton({Id = "reset_all", Name = "すべて初期化", Description = "確認ダイアログが出ます", Callback = function()
		CK.Confirm({Title = "初期化", Message = "すべての設定を初期値に戻します。よろしいですか？", OnYes = function() CK.ResetAll() end})
	end})
	tab:AddSection("情報")
	tab:AddLabel({Id = "about", Text = "COOLKID GUI V2  v" .. CK.Version .. "\n機能の追加方法はスクリプト末尾のコメントを参照"})
end)

------------------------------------------------------------------
-- 起動
------------------------------------------------------------------
do
	local vp = ViewSize()
	winCenter = Vector2.new(vp.X / 2, vp.Y / 2)
	bubblePos = Vector2.new(60, math.max(vp.Y * 0.3, 80))
	UpdateScale()
	Win.Position = UDim2.fromOffset(winCenter.X, winCenter.Y)
	-- 開くアニメーション
	WinScale.Scale = 0.05 * respScale
	Win.GroupTransparency = 1
	local ti = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(WinScale, ti, {Scale = respScale}):Play()
	TweenService:Create(Win, TweenInfo.new(0.3), {GroupTransparency = 0}):Play()
	CK.RefreshStatus()
	CK.Notify("COOLKID GUI V2 を起動しました", "success")
end

--[[
===================== 機能の追加方法 (サンプル) =====================
GUI本体は変更せず、別のスクリプトや別ファイルから次のように追加できます。
(同じ Id を二重に登録すると、警告が出て登録されません)

	local CK = getgenv().COOLKID_V2
	CK.RegisterModule("MyAddon", function(CK)
		local tab = CK.AddTab("追加機能")

		-- トグル: ON/OFFと実際の処理が連動します (エラー時は状態を戻して通知)
		local conn
		tab:AddToggle({
			Id = "my_loop", Name = "毎秒メッセージ", Description = "ONの間、毎秒通知を出します",
			Callback = function(on)
				if on then
					conn = task.spawn(function()
						while true do task.wait(1); CK.Notify("1秒経過", "info", 1) end
					end)
				elseif conn then
					task.cancel(conn); conn = nil
				end
			end,
			Cleanup = function() if conn then task.cancel(conn) end end,   -- 削除/終了時の後片付け
		})

		-- ボタン: 連打しても二重実行されません
		tab:AddButton({Id = "my_btn", Name = "挨拶", Callback = function() CK.Notify("こんにちは！", "success") end})

		-- ドロップダウン / スライダー / 入力欄
		tab:AddDropdown({Id = "my_dd", Name = "モード", Options = {"A", "B", "C"}, Default = "A", Callback = function(v) end})
		tab:AddSlider({Id = "my_sl", Name = "強さ", Min = 0, Max = 10, Step = 1, Default = 5, Callback = function(v) end})
		tab:AddNumberInput({Id = "my_num", Name = "回数", Min = 1, Max = 99, Default = 3, Integer = true, Callback = function(n) end})
		tab:AddTextInput({Id = "my_txt", Name = "名前", Default = "", Callback = function(t) end})

		-- 戻り値の関数は CK.UnloadModule("MyAddon") 時に呼ばれます
		return function() end
	end)

	-- 後から外したいとき:
	-- CK.UnloadModule("MyAddon")   -- 部品・タブ・接続がすべて解除されます

自分でホストした短い読み込みコードの例 (自分が管理するURLだけを使ってください):
	loadstring(game:HttpGet("https://あなたのURL/COOLKID_GUI_V2.lua"))()
=====================================================================
]]
