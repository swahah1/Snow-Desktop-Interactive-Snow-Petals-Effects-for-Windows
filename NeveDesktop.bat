@echo off
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$f=[IO.File]::ReadAllText('%~f0'); $i=$f.IndexOf(([string][char]10)+'#PS'+'START'); iex $f.Substring($i)"
exit
#PSSTART
$ErrorActionPreference = 'Stop'
try {
Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

public class WinInfo { public long H; public int L, T, R, B; }
public class Pile { public int n; public float[] s, p; public Pile(int n) { this.n = n; s = new float[n]; p = new float[n]; } }
public class Part { public float x, y, r, vy, s, ph, a; public bool snow; public Brush br; }
public class SnowBall { public float x, y, vx, vy; public long ig; }
public class Splat { public long key; public float dx, dy; public double born; public float[] ox, oy, rr; }
public class Puff { public float x, y, vx, vy; public int life; }

public static class Native
{
    public delegate bool EnumProc(IntPtr h, IntPtr lp);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] public struct BLEND { public byte Op, Flags, Alpha, Format; }

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")] public static extern int GetWindowLong(IntPtr h, int i);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out RECT r, int size);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int attr, out int v, int size);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int vk);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
    [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr o);
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UpdateLayeredWindow(IntPtr h, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
        IntPtr hdcSrc, ref POINT pprSrc, int crKey, ref BLEND pblend, int flags);

    public static List<WinInfo> ListWindows(List<long> skip, int sw, int sh)
    {
        List<WinInfo> res = new List<WinInfo>();
        EnumProc cb = delegate(IntPtr h, IntPtr lp)
        {
            try
            {
                if (skip.Contains(h.ToInt64()) || !IsWindowVisible(h) || IsIconic(h)) return true;
                if ((GetWindowLong(h, -20) & 0x20) != 0) return true;
                int cl; DwmGetWindowAttribute(h, 14, out cl, 4);
                if (cl != 0) return true;
                StringBuilder sb = new StringBuilder(64);
                GetClassName(h, sb, 64);
                string c = sb.ToString();
                if (c == "Progman" || c == "WorkerW" || c == "Windows.UI.Core.CoreWindow") return true;
                RECT r;
                if (DwmGetWindowAttribute(h, 9, out r, 16) != 0) GetWindowRect(h, out r);
                int w = r.Right - r.Left, hh = r.Bottom - r.Top;
                if (w < 120 || hh < 30) return true;
                if (w >= sw && hh >= sh && !IsZoomed(h)) return true;
                WinInfo wi = new WinInfo();
                wi.H = h.ToInt64(); wi.L = r.Left; wi.T = r.Top; wi.R = r.Right; wi.B = r.Bottom;
                res.Add(wi);
            }
            catch (Exception) { }
            return true;
        };
        EnumWindows(cb, IntPtr.Zero);
        return res;
    }
}

public class OverlayForm : Form
{
    public OverlayForm()
    {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual;
    }
    protected override CreateParams CreateParams
    {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x8000000; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }
}

public class CatcherForm : Form
{
    public CatcherForm()
    {
        FormBorderStyle = FormBorderStyle.None; ShowInTaskbar = false; TopMost = true;
        StartPosition = FormStartPosition.Manual; BackColor = Color.Black; Opacity = 0.01;
    }
    protected override CreateParams CreateParams
    {
        get { CreateParams cp = base.CreateParams; cp.ExStyle |= 0x80 | 0x8000000; return cp; }
    }
    protected override bool ShowWithoutActivation { get { return true; } }
}

public class Neve
{
    const int COL = 3;
    const float MAXPILE = 34f;
    static readonly float[,] PETAL = { { -1f, 0f }, { -.45f, -.65f }, { .45f, -.65f }, { 1f, 0f }, { .45f, .65f }, { -.45f, .65f } };

    int W, H;
    Rectangle bounds;
    Bitmap frame, sculpt;
    Graphics g, gs;
    OverlayForm ov; CatcherForm cat; Form panel;
    System.Windows.Forms.Timer timer;
    TrackBar tbAmount, tbWind, tbSize;
    Button btnPause;
    Random rnd = new Random();

    List<long> skip = new List<long>();
    List<WinInfo> wins = new List<WinInfo>();
    Dictionary<long, WinInfo> byKey = new Dictionary<long, WinInfo>();
    Dictionary<long, Pile> piles = new Dictionary<long, Pile>();
    List<Part> parts = new List<Part>();
    List<SnowBall> balls = new List<SnowBall>();
    List<Splat> splats = new List<Splat>();
    List<Puff> puffs = new List<Puff>();
    List<Bitmap> undo = new List<Bitmap>();

    string effect = "neve", mode = "nessuna", tool = "pennello";
    bool paused = false, dragging = false, erasing = false, aiming = false, shownErr = false;
    float lastX, lastY, ax, ay, mx, my;
    double t = 0; int frameNo = 0;
    DateTime t0 = DateTime.Now;

    SolidBrush snowBrush = new SolidBrush(Color.FromArgb(245, 255, 255, 255));
    SolidBrush petalPileBrush = new SolidBrush(Color.FromArgb(245, 255, 183, 204));
    SolidBrush clearBrush = new SolidBrush(Color.FromArgb(0, 0, 0, 0));
    Pen edgePen = new Pen(Color.FromArgb(200, 170, 195, 225), 1.2f);
    Pen flakePen = new Pen(Color.FromArgb(150, 170, 195, 225), 1f);
    Brush[] petalBrushes;

    public Form Panel { get { return panel; } }

    float R(float a, float b) { return a + (float)rnd.NextDouble() * (b - a); }

    public Neve()
    {
        bounds = Screen.PrimaryScreen.Bounds; W = bounds.Width; H = bounds.Height;
        frame = new Bitmap(W, H, PixelFormat.Format32bppPArgb);
        g = Graphics.FromImage(frame); g.SmoothingMode = SmoothingMode.AntiAlias;
        sculpt = new Bitmap(W, H, PixelFormat.Format32bppPArgb);
        gs = Graphics.FromImage(sculpt); gs.SmoothingMode = SmoothingMode.AntiAlias;

        string[] pk = { "#ffc1d6", "#ffb0c8", "#ffd6e2", "#ff9fbd", "#fff0f5" };
        petalBrushes = new Brush[pk.Length];
        for (int i = 0; i < pk.Length; i++) petalBrushes[i] = new SolidBrush(ColorTranslator.FromHtml(pk[i]));

        ov = new OverlayForm(); ov.Bounds = bounds;
        cat = new CatcherForm(); cat.Bounds = bounds;
        BuildPanel();

        skip.Add(ov.Handle.ToInt64()); skip.Add(cat.Handle.ToInt64()); skip.Add(panel.Handle.ToInt64());

        cat.MouseDown += MDown; cat.MouseMove += MMove; cat.MouseUp += MUp;
        cat.MouseWheel += delegate(object s, MouseEventArgs e)
        {
            int v = tbSize.Value + (e.Delta > 0 ? 2 : -2);
            tbSize.Value = Math.Max(tbSize.Minimum, Math.Min(tbSize.Maximum, v));
        };

        ov.Show();
        RefreshWins();
        timer = new System.Windows.Forms.Timer(); timer.Interval = 30; timer.Tick += OnTick; timer.Start();
        panel.FormClosed += delegate { timer.Stop(); ov.Close(); cat.Close(); };
    }

    // ---------------------------------------------------------------- pannello
    GroupBox Group(string title, int top, int h)
    {
        GroupBox gb = new GroupBox(); gb.Text = title; gb.Left = 8; gb.Top = top; gb.Width = 274; gb.Height = h;
        panel.Controls.Add(gb); return gb;
    }
    Label Lbl(Control p, string text, int x, int y)
    {
        Label l = new Label(); l.Text = text; l.Left = x; l.Top = y; l.AutoSize = true; p.Controls.Add(l); return l;
    }
    TrackBar Track(Control p, int x, int y, int min, int max, int val)
    {
        TrackBar tb = new TrackBar(); tb.Left = x; tb.Top = y; tb.Width = 258; tb.Height = 30;
        tb.Minimum = min; tb.Maximum = max; tb.Value = val; tb.TickStyle = TickStyle.None; p.Controls.Add(tb); return tb;
    }
    Button Btn(Control p, string text, int x, int y, int w, EventHandler h)
    {
        Button b = new Button(); b.Text = text; b.Left = x; b.Top = y; b.Width = w; b.Height = 26;
        b.Click += h; p.Controls.Add(b); return b;
    }
    RadioButton Radio(Control p, string text, int x, int y, bool chk, Action onSel)
    {
        RadioButton rb = new RadioButton(); rb.Text = text; rb.Left = x; rb.Top = y; rb.AutoSize = true; rb.Checked = chk;
        p.Controls.Add(rb);
        rb.CheckedChanged += delegate { if (rb.Checked) onSel(); };
        return rb;
    }

    void BuildPanel()
    {
        panel = new Form();
        panel.Font = new Font("Segoe UI", 9f);
        panel.AutoScaleDimensions = new SizeF(96f, 96f);
        panel.AutoScaleMode = AutoScaleMode.Dpi;
        panel.Text = "Neve sul Desktop";
        panel.FormBorderStyle = FormBorderStyle.FixedSingle; panel.MaximizeBox = false; panel.TopMost = true;
        panel.StartPosition = FormStartPosition.Manual;
        panel.ClientSize = new Size(290, 510);
        panel.Location = new Point(Math.Max(0, W - 340), 50);

        GroupBox g1 = Group("Effetto sul desktop", 6, 52);
        Radio(g1, "Neve", 10, 20, true, delegate { effect = "neve"; });
        Radio(g1, "Petali", 90, 20, false, delegate { effect = "petali"; });
        Radio(g1, "Spento", 180, 20, false, delegate { effect = "spento"; });

        GroupBox g2 = Group("Quantit\u00e0 e vento", 62, 118);
        Lbl(g2, "Quantit\u00e0", 10, 18); tbAmount = Track(g2, 8, 32, 0, 400, 120);
        Lbl(g2, "Vento (sinistra / destra)", 10, 66); tbWind = Track(g2, 8, 80, -60, 60, 0);

        GroupBox g3 = Group("Mouse", 186, 96);
        Radio(g3, "Normale (clicchi sul desktop)", 10, 20, true, delegate { mode = "nessuna"; OnMode(); });
        Radio(g3, "Scolpisci la neve", 10, 44, false, delegate { mode = "scultura"; OnMode(); });
        Radio(g3, "Lancia palle di neve (trascina e rilascia)", 10, 68, false, delegate { mode = "palle"; OnMode(); });

        GroupBox g4 = Group("Scultura (clic destro = gomma)", 288, 152);
        Radio(g4, "Pennello di neve", 10, 20, true, delegate { tool = "pennello"; });
        Radio(g4, "Pupazzo di neve (timbro)", 10, 42, false, delegate { tool = "pupazzo"; });
        Lbl(g4, "Dimensione (anche con la rotella)", 10, 66); tbSize = Track(g4, 8, 80, 6, 60, 18);
        Btn(g4, "Annulla", 10, 116, 80, delegate { DoUndo(); });
        Btn(g4, "Cancella sculture", 98, 116, 130, delegate { ClearSculpt(); });

        Btn(panel, "Spazza via neve", 10, 450, 120, delegate { ClearSnow(); });
        btnPause = Btn(panel, "Pausa", 136, 450, 70, delegate { paused = !paused; btnPause.Text = paused ? "Riprendi" : "Pausa"; });
        Btn(panel, "Esci", 212, 450, 68, delegate { panel.Close(); });
        Lbl(panel, "Emergenza: premi Ctrl+Alt+Q", 10, 484);
    }

    void OnMode()
    {
        if (mode == "nessuna") { aiming = false; dragging = false; erasing = false; cat.Hide(); }
        else { cat.Cursor = (mode == "palle") ? Cursors.Cross : Cursors.Hand; cat.Show(); Relift(); }
    }

    void Relift()
    {
        IntPtr top = new IntPtr(-1); uint fl = 0x0002 | 0x0001 | 0x0010;
        if (cat.Visible) Native.SetWindowPos(cat.Handle, top, 0, 0, 0, 0, fl);
        Native.SetWindowPos(ov.Handle, top, 0, 0, 0, 0, fl);
        Native.SetWindowPos(panel.Handle, top, 0, 0, 0, 0, fl);
    }

    // ---------------------------------------------------------------- ciclo
    void OnTick(object sender, EventArgs ev)
    {
        try
        {
            frameNo++; t = (DateTime.Now - t0).TotalSeconds;
            if (frameNo % 5 == 1) RefreshWins();
            if (!paused) { StepParts(); StepBalls(); StepPuffs(); }
            Render();
            if ((Native.GetAsyncKeyState(0x11) & 0x8000) != 0 && (Native.GetAsyncKeyState(0x12) & 0x8000) != 0
                && (Native.GetAsyncKeyState(0x51) & 0x8000) != 0) { panel.Close(); return; }
            if (frameNo % 50 == 0) Relift();
        }
        catch (Exception ex)
        {
            if (!shownErr) { shownErr = true; MessageBox.Show(ex.ToString(), "Errore"); }
        }
    }

    void RefreshWins()
    {
        wins = Native.ListWindows(skip, W, H);
        byKey.Clear();
        foreach (WinInfo w in wins) if (!byKey.ContainsKey(w.H)) byKey[w.H] = w;
    }

    WinInfo TopAt(float x, float y)
    {
        foreach (WinInfo w in wins) if (w.L <= x && x < w.R && w.T <= y && y < w.B) return w;
        return null;
    }

    // ---------------------------------------------------------------- cumuli
    float Tot(Pile p, int i) { return p.s[i] + p.p[i]; }

    void Resize(Pile p, int n)
    {
        float[] a = new float[n]; float[] b = new float[n];
        for (int i = 0; i < n; i++) { int j = Math.Min(p.n - 1, i * p.n / n); a[i] = p.s[j]; b[i] = p.p[j]; }
        p.s = a; p.p = b; p.n = n;
    }

    void DropOn(long key, int l, int w, float x, bool snow)
    {
        int n = w / COL + 1;
        Pile p;
        if (!piles.TryGetValue(key, out p)) { p = new Pile(n); piles[key] = p; }
        else if (p.n != n) Resize(p, n);
        int c = (int)((x - l) / COL);
        c = Math.Max(0, Math.Min(p.n - 1, c));
        for (int k = 0; k < 6; k++)
        {
            int best = c;
            for (int d = -1; d <= 1; d += 2)
            {
                int j = c + d;
                if (j >= 0 && j < p.n && Tot(p, j) < Tot(p, best) - 1.2f) best = j;
            }
            if (best == c) break;
            c = best;
        }
        if (Tot(p, c) >= MAXPILE) return;
        if (snow) p.s[c] += 0.9f; else p.p[c] += 0.45f;
    }

    float[] Smooth(float[] a)
    {
        int n = a.Length; float[] r = new float[n];
        for (int i = 0; i < n; i++) r[i] = (a[Math.Max(0, i - 1)] + 2 * a[i] + a[Math.Min(n - 1, i + 1)]) / 4f;
        return r;
    }

    void DrawPile(Pile p, int l, int t0i)
    {
        int n = p.n; float[] s = Smooth(p.s); float[] q = Smooth(p.p);
        bool anyS = false, anyP = false;
        for (int i = 0; i < n; i++) { if (s[i] > 0.3f) anyS = true; if (q[i] > 0.3f) anyP = true; }
        if (anyS)
        {
            PointF[] poly = new PointF[n + 2]; PointF[] top = new PointF[n];
            for (int i = 0; i < n; i++) { top[i] = new PointF(l + i * COL, t0i - s[i]); poly[i] = top[i]; }
            poly[n] = new PointF(l + (n - 1) * COL, t0i); poly[n + 1] = new PointF(l, t0i);
            g.FillPolygon(snowBrush, poly); g.DrawLines(edgePen, top);
        }
        if (anyP)
        {
            PointF[] poly = new PointF[2 * n];
            for (int i = 0; i < n; i++)
            {
                poly[i] = new PointF(l + i * COL, t0i - s[i] - q[i]);
                poly[2 * n - 1 - i] = new PointF(l + i * COL, t0i - s[i]);
            }
            g.FillPolygon(petalPileBrush, poly);
        }
    }

    // ---------------------------------------------------------------- particelle
    void Spawn()
    {
        Part p = new Part(); p.snow = (effect == "neve");
        if (p.snow) { p.r = R(1.6f, 4.2f); p.vy = 0.9f + p.r * 0.45f; }
        else { p.r = R(4f, 8f); p.vy = R(0.9f, 1.8f); p.br = petalBrushes[rnd.Next(petalBrushes.Length)]; }
        p.x = R(-0.3f * W, 1.3f * W); p.y = -10f; p.s = R(0.6f, 1.4f); p.ph = R(0f, 6.28f); p.a = R(0f, 6.28f);
        parts.Add(p);
    }

    bool TryLand(Part f, float oy)
    {
        float x = f.x, y = f.y;
        for (int i = 0; i < wins.Count; i++)
        {
            WinInfo w = wins[i];
            if (w.T > 4 && w.L <= x && x < w.R && oy <= w.T && w.T <= y)
            {
                bool covered = false;
                for (int j = 0; j < i; j++)
                {
                    WinInfo o = wins[j];
                    if (o.L <= x && x < o.R && o.T <= w.T && w.T < o.B) { covered = true; break; }
                }
                if (covered) continue;
                DropOn(w.H, w.L, w.R - w.L, x, f.snow);
                return true;
            }
        }
        if (y >= H) { DropOn(-1, 0, W, x, f.snow); return true; }
        return false;
    }

    void StepParts()
    {
        if (effect != "spento")
            for (int i = 0; i < 3; i++) if (parts.Count < tbAmount.Value) Spawn();
        float wind = tbWind.Value / 10f + (float)Math.Sin(t * 0.4) * 0.6f;
        for (int i = parts.Count - 1; i >= 0; i--)
        {
            Part f = parts[i]; float oy = f.y;
            f.ph += 0.07f;
            f.x += wind * f.s + (float)Math.Sin(f.ph) * (f.snow ? 0.5f : 1.2f);
            f.y += f.vy;
            if (TryLand(f, oy) || f.y > H + 20 || f.x < -0.6f * W || f.x > 1.6f * W) parts.RemoveAt(i);
        }
    }

    // ---------------------------------------------------------------- scultura
    void DrawSnowball(Graphics gg, float x, float y, float r)
    {
        using (GraphicsPath p = new GraphicsPath())
        {
            p.AddEllipse(x - r, y - r, 2 * r, 2 * r);
            using (PathGradientBrush b = new PathGradientBrush(p))
            {
                b.CenterPoint = new PointF(x - r * 0.3f, y - r * 0.35f);
                b.CenterColor = Color.White;
                b.SurroundColors = new Color[] { Color.FromArgb(255, 196, 214, 234) };
                gg.FillPath(b, p);
            }
        }
        using (Pen pen = new Pen(Color.FromArgb(110, 120, 150, 190), 1f)) gg.DrawEllipse(pen, x - r, y - r, 2 * r, 2 * r);
    }

    void Snowman(float x, float y, float s)
    {
        float r1 = s * 1.2f, r2 = s * 0.9f, r3 = s * 0.65f;
        float c1 = y - r1, c2 = c1 - (r1 + r2) * 0.85f, c3 = c2 - (r2 + r3) * 0.85f;
        DrawSnowball(gs, x, c1, r1); DrawSnowball(gs, x, c2, r2); DrawSnowball(gs, x, c3, r3);
        using (Brush dark = new SolidBrush(Color.FromArgb(34, 34, 34)))
        using (Brush carrot = new SolidBrush(Color.FromArgb(255, 140, 26)))
        using (Pen arm = new Pen(Color.FromArgb(107, 74, 43), 3f))
        {
            float ee = r3 * 0.09f;
            for (int sx = -1; sx <= 1; sx += 2)
            {
                gs.FillEllipse(dark, x + sx * r3 * 0.35f - ee, c3 - r3 * 0.2f - ee, 2 * ee, 2 * ee);
                gs.DrawLine(arm, x + sx * r2 * 0.85f, c2, x + sx * (r2 + r1 * 0.9f), c2 - r2 * 0.6f);
            }
            gs.FillPolygon(carrot, new PointF[] { new PointF(x, c3), new PointF(x + r3, c3 + r3 * 0.12f), new PointF(x, c3 + r3 * 0.25f) });
            float[] ks = { -0.4f, 0.05f, 0.5f };
            foreach (float k in ks) gs.FillEllipse(dark, x - 3, c2 + r2 * k - 3, 6, 6);
            gs.FillRectangle(dark, x - r3 * 0.7f, c3 - r3 * 1.5f, r3 * 1.4f, r3 * 0.65f);
            gs.FillRectangle(dark, x - r3 * 1.0f, c3 - r3 * 0.95f, r3 * 2f, r3 * 0.15f);
        }
    }

    Bitmap CopyBmp(Bitmap src)
    {
        Bitmap b = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppPArgb);
        using (Graphics gg = Graphics.FromImage(b))
        {
            gg.CompositingMode = CompositingMode.SourceCopy;
            gg.DrawImage(src, new Rectangle(0, 0, src.Width, src.Height), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel);
        }
        return b;
    }

    void PushUndo()
    {
        undo.Add(CopyBmp(sculpt));
        if (undo.Count > 5) { undo[0].Dispose(); undo.RemoveAt(0); }
    }

    void DoUndo()
    {
        if (undo.Count == 0) return;
        Bitmap snap = undo[undo.Count - 1]; undo.RemoveAt(undo.Count - 1);
        gs.Dispose(); sculpt.Dispose();
        sculpt = snap; gs = Graphics.FromImage(sculpt); gs.SmoothingMode = SmoothingMode.AntiAlias;
    }

    void ClearSculpt() { PushUndo(); gs.Clear(Color.Transparent); }

    void ClearSnow()
    {
        piles.Clear(); splats.Clear(); parts.Clear(); balls.Clear(); puffs.Clear();
    }

    void EraseAt(float x, float y)
    {
        float r = tbSize.Value;
        gs.CompositingMode = CompositingMode.SourceCopy;
        gs.FillEllipse(clearBrush, x - r, y - r, 2 * r, 2 * r);
        gs.CompositingMode = CompositingMode.SourceOver;
    }

    void MDown(object s, MouseEventArgs e)
    {
        mx = e.X; my = e.Y;
        if (e.Button == MouseButtons.Left)
        {
            if (mode == "scultura")
            {
                PushUndo();
                if (tool == "pupazzo") Snowman(e.X, e.Y, tbSize.Value);
                else { dragging = true; lastX = e.X; lastY = e.Y; DrawSnowball(gs, e.X, e.Y, tbSize.Value * 0.6f); }
            }
            else if (mode == "palle") { aiming = true; ax = e.X; ay = e.Y; }
        }
        else if (e.Button == MouseButtons.Right && mode == "scultura")
        {
            PushUndo(); erasing = true; EraseAt(e.X, e.Y);
        }
    }

    void MMove(object s, MouseEventArgs e)
    {
        mx = e.X; my = e.Y;
        if (dragging)
        {
            float dx = mx - lastX, dy = my - lastY;
            float dist = (float)Math.Sqrt(dx * dx + dy * dy);
            float step = Math.Max(3f, tbSize.Value * 0.3f);
            int n = (int)(dist / step);
            for (int k = 1; k <= n; k++) DrawSnowball(gs, lastX + dx * k / n, lastY + dy * k / n, tbSize.Value * 0.6f);
            if (n > 0) { lastX = mx; lastY = my; }
        }
        if (erasing) EraseAt(mx, my);
    }

    void MUp(object s, MouseEventArgs e)
    {
        dragging = false; erasing = false;
        if (aiming)
        {
            aiming = false;
            float vx = (e.X - ax) * 0.3f, vy = (e.Y - ay) * 0.3f;
            float sp = (float)Math.Sqrt(vx * vx + vy * vy);
            if (sp < 2f) return;
            if (sp > 48f) { vx = vx * 48f / sp; vy = vy * 48f / sp; }
            SnowBall b = new SnowBall(); b.x = ax; b.y = ay; b.vx = vx; b.vy = vy;
            WinInfo top = TopAt(ax, ay); b.ig = (top != null) ? top.H : -2;
            balls.Add(b);
        }
    }

    // ---------------------------------------------------------------- palle di neve
    void AddPuff(float x, float y)
    {
        for (int i = 0; i < 8; i++)
        {
            float a = R(0f, 6.28f), sp = R(1f, 4f);
            Puff p = new Puff(); p.x = x; p.y = y; p.vx = (float)Math.Cos(a) * sp; p.vy = (float)Math.Sin(a) * sp - 1f; p.life = 14;
            puffs.Add(p);
        }
    }

    void AddSplat(WinInfo w, float px, float py)
    {
        Splat s = new Splat(); s.key = w.H; s.dx = px - w.L; s.dy = py - w.T; s.born = t;
        int cnt = rnd.Next(7, 12);
        s.ox = new float[cnt]; s.oy = new float[cnt]; s.rr = new float[cnt];
        for (int k = 0; k < cnt; k++)
        {
            if (k == 0) { s.ox[k] = 0; s.oy[k] = 0; s.rr[k] = R(9f, 13f); }
            else
            {
                float a = R(0f, 6.28f), d = R(6f, 24f);
                s.ox[k] = (float)Math.Cos(a) * d; s.oy[k] = (float)Math.Sin(a) * d; s.rr[k] = R(2f, 6f);
            }
        }
        splats.Add(s); AddPuff(px, py);
        while (splats.Count > 120) splats.RemoveAt(0);
    }

    void StepBalls()
    {
        for (int i = balls.Count - 1; i >= 0; i--)
        {
            SnowBall b = balls[i];
            float ox = b.x, oy = b.y;
            b.vy += 0.7f;
            float nx = ox + b.vx, ny = oy + b.vy;
            int n = (int)(Math.Max(Math.Abs(nx - ox), Math.Abs(ny - oy)) / 6f) + 1;
            WinInfo hit = null; float hx = 0, hy = 0;
            for (int k = 1; k <= n; k++)
            {
                float px = ox + (nx - ox) * k / n, py = oy + (ny - oy) * k / n;
                WinInfo w = TopAt(px, py);
                if (w == null) b.ig = -2;
                else if (w.H != b.ig) { hit = w; hx = px; hy = py; break; }
            }
            if (hit != null) { AddSplat(hit, hx, hy); balls.RemoveAt(i); continue; }
            b.x = nx; b.y = ny;
            if (ny >= H) { AddPuff(nx, H - 2); balls.RemoveAt(i); continue; }
            if (nx < -100 || nx > W + 100) balls.RemoveAt(i);
        }
    }

    void StepPuffs()
    {
        for (int i = puffs.Count - 1; i >= 0; i--)
        {
            Puff p = puffs[i]; p.life--;
            if (p.life <= 0) { puffs.RemoveAt(i); continue; }
            p.x += p.vx; p.y += p.vy; p.vy += 0.25f;
        }
    }

    // ---------------------------------------------------------------- disegno
    void Render()
    {
        g.Clear(Color.Transparent);
        g.DrawImage(sculpt, new Rectangle(0, 0, W, H), 0, 0, W, H, GraphicsUnit.Pixel);

        List<long> dead = null;
        foreach (KeyValuePair<long, Pile> kv in piles)
        {
            int l, tp, w;
            if (kv.Key == -1) { l = 0; tp = H; w = W; }
            else
            {
                WinInfo wi;
                if (!byKey.TryGetValue(kv.Key, out wi)) { if (dead == null) dead = new List<long>(); dead.Add(kv.Key); continue; }
                l = wi.L; tp = wi.T; w = wi.R - wi.L;
            }
            int n = w / COL + 1;
            if (kv.Value.n != n) Resize(kv.Value, n);
            DrawPile(kv.Value, l, tp);
        }
        if (dead != null) foreach (long k in dead) piles.Remove(k);

        for (int i = splats.Count - 1; i >= 0; i--)
        {
            Splat s = splats[i]; WinInfo wi;
            if (t - s.born > 30 || !byKey.TryGetValue(s.key, out wi)) { splats.RemoveAt(i); continue; }
            for (int k = 0; k < s.rr.Length; k++)
            {
                float x = wi.L + s.dx + s.ox[k], y = wi.T + s.dy + s.oy[k], r = s.rr[k];
                g.FillEllipse(snowBrush, x - r, y - r, 2 * r, 2 * r);
                g.DrawEllipse(edgePen, x - r, y - r, 2 * r, 2 * r);
            }
        }

        PointF[] pts = new PointF[6];
        foreach (Part p in parts)
        {
            if (p.snow)
            {
                g.FillEllipse(snowBrush, p.x - p.r, p.y - p.r, 2 * p.r, 2 * p.r);
                g.DrawEllipse(flakePen, p.x - p.r, p.y - p.r, 2 * p.r, 2 * p.r);
            }
            else
            {
                float a = p.a + p.ph * 0.5f;
                float flip = 0.35f + 0.65f * (float)Math.Abs(Math.Cos(p.ph * 1.3));
                float ca = (float)Math.Cos(a), sa = (float)Math.Sin(a);
                for (int i = 0; i < 6; i++)
                {
                    float px = PETAL[i, 0] * p.r, py = PETAL[i, 1] * p.r * flip;
                    pts[i] = new PointF(p.x + px * ca - py * sa, p.y + px * sa + py * ca);
                }
                g.FillClosedCurve(p.br, pts);
            }
        }

        foreach (SnowBall b in balls)
        {
            g.FillEllipse(snowBrush, b.x - 9, b.y - 9, 18, 18);
            g.DrawEllipse(edgePen, b.x - 9, b.y - 9, 18, 18);
        }
        foreach (Puff p in puffs)
        {
            float r = 1f + p.life * 0.22f;
            using (SolidBrush pb = new SolidBrush(Color.FromArgb(Math.Min(255, p.life * 18), 255, 255, 255)))
                g.FillEllipse(pb, p.x - r, p.y - r, 2 * r, 2 * r);
        }
        if (aiming)
        {
            using (Pen ap = new Pen(Color.FromArgb(230, 90, 160, 255), 3f))
            {
                ap.DashStyle = DashStyle.Dash;
                g.DrawLine(ap, ax, ay, mx, my);
                g.FillEllipse(Brushes.White, ax - 6, ay - 6, 12, 12);
            }
        }
        Present();
    }

    void Present()
    {
        IntPtr screenDc = Native.GetDC(IntPtr.Zero);
        IntPtr memDc = Native.CreateCompatibleDC(screenDc);
        IntPtr hBmp = IntPtr.Zero, old = IntPtr.Zero;
        try
        {
            hBmp = frame.GetHbitmap(Color.FromArgb(0));
            old = Native.SelectObject(memDc, hBmp);
            Native.SIZE size = new Native.SIZE(); size.cx = W; size.cy = H;
            Native.POINT src = new Native.POINT();
            Native.POINT dst = new Native.POINT(); dst.x = bounds.X; dst.y = bounds.Y;
            Native.BLEND bf = new Native.BLEND(); bf.Op = 0; bf.Flags = 0; bf.Alpha = 255; bf.Format = 1;
            Native.UpdateLayeredWindow(ov.Handle, screenDc, ref dst, ref size, memDc, ref src, 0, ref bf, 2);
        }
        finally
        {
            if (hBmp != IntPtr.Zero) { Native.SelectObject(memDc, old); Native.DeleteObject(hBmp); }
            Native.DeleteDC(memDc); Native.ReleaseDC(IntPtr.Zero, screenDc);
        }
    }
}

public static class NeveMain
{
    public static void Run()
    {
        Native.SetProcessDPIAware();
        Application.EnableVisualStyles();
        try { Application.SetCompatibleTextRenderingDefault(false); } catch (Exception) { }
        Neve n = new Neve();
        Application.Run(n.Panel);
    }
}
'@
[NeveMain]::Run()
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    $msg = $_.Exception.Message + "`r`n`r`n" + ($Error | Out-String)
    [void][System.Windows.Forms.MessageBox]::Show($msg, 'Errore - Neve sul Desktop')
}
