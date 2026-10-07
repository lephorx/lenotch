using System;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using Lenotch.Core;
using Lenotch.Notch;
using Lenotch.Services;

namespace Lenotch.Views;

/// Files dropped on the notch, with a Share target on the right.
public sealed class ShelfView : NotchContentView
{
    private readonly NotchModel model;
    private readonly Grid dropZone = new();
    private readonly Rectangle outline;
    private string itemsKey = "";

    private ShelfStore Shelf => model.Services.Shelf;

    public ShelfView(NotchModel model)
    {
        this.model = model;
        var forward = model.PageMovesForward;
        var s = model.Settings;
        ColumnDefinitions.Add(new ColumnDefinition());
        ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        outline = new Rectangle
        {
            RadiusX = 26,
            RadiusY = 26,
            Stroke = Ui.White(0.15),
            StrokeThickness = 1.5,
            StrokeDashArray = new DoubleCollection { 3.3, 2.7 },
        };
        if (s.ShowFileShelf)
        {
            var zone = new Grid { Background = Brushes.Transparent, Children = { outline, dropZone } };
            zone.ContextMenu = ShelfMenu();
            zone.ContextMenuOpening += (_, e) => { if (Shelf.Items.Count == 0) e.Handled = true; };
            zone.SlideIn(0, forward);
            Children.Add(zone);
            AllowDrop = true;
            DragEnter += (_, _) => Highlight(true);
            DragLeave += (_, _) => Highlight(false);
            Drop += (_, _) => Highlight(false);
        }
        if (s.ShowShare)
        {
            // Without the file shelf, Share stretches across the tab.
            var share = ShareTarget(stretched: !s.ShowFileShelf);
            if (s.ShowFileShelf)
            {
                share.Margin = new Thickness(12, 0, 0, 0);
                SetColumn(share, 1);
            }
            else
            {
                SetColumnSpan(share, 2);
            }
            share.SlideIn(1, forward);
            Children.Add(share);
        }
        Refresh();
    }

    private void Highlight(bool targeted) => outline.Stroke = Ui.White(targeted ? 0.5 : 0.15);

    private ContextMenu ShelfMenu()
    {
        var menu = new ContextMenu();
        menu.Items.Add(MenuItem("Share All", () => model.Share?.Invoke(Shelf.Items.ToList())));
        menu.Items.Add(MenuItem("Show in Explorer", () => { if (Shelf.Items.Count > 0) ShelfStore.ShowInExplorer(Shelf.Items[0]); }));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItem("Clear Shelf", Shelf.RemoveAll));
        return menu;
    }

    public static MenuItem MenuItem(string title, Action action)
    {
        var item = new MenuItem { Header = title };
        item.Click += (_, _) => action();
        return item;
    }

    public override void Refresh()
    {
        var key = string.Join("|", Shelf.Items);
        if (key == itemsKey && dropZone.Children.Count > 0) return;
        itemsKey = key;
        dropZone.Children.Clear();
        if (Shelf.Items.Count == 0)
        {
            var empty = Ui.VStack(6, Ui.Icon(Glyphs.Download, 22, Ui.White(0.45)),
                Ui.Text("Drop files here", 12, FontWeights.Medium, Ui.White(0.45)));
            empty.HorizontalAlignment = HorizontalAlignment.Center;
            empty.VerticalAlignment = VerticalAlignment.Center;
            ((TextBlock)empty.Children[1]).HorizontalAlignment = HorizontalAlignment.Center;
            dropZone.Children.Add(empty);
            return;
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        foreach (var path in Shelf.Items) row.Children.Add(Item(path));
        var scroll = new ScrollViewer
        {
            Content = row,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden,
            VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        // The wheel scrolls a full shelf sideways.
        scroll.PreviewMouseWheel += (_, e) =>
        {
            scroll.ScrollToHorizontalOffset(scroll.HorizontalOffset - e.Delta / 2.0);
            e.Handled = true;
        };
        dropZone.Children.Add(scroll);
    }

    private FrameworkElement Item(string path)
    {
        var icon = new Image { Source = Shelf.Icon(path), Width = 42, Height = 42 };
        var name = new TextBlock
        {
            Text = System.IO.Path.GetFileName(path.TrimEnd('\\')),
            FontSize = 10,
            FontFamily = Ui.TextFont,
            Foreground = Ui.White(0.8),
            TextWrapping = TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextAlignment = TextAlignment.Center,
            MaxHeight = 28,
            Width = 66,
            Margin = new Thickness(0, 4, 0, 0),
        };
        var stack = new StackPanel { Children = { icon, name } };
        var remove = new Border
        {
            Width = 16,
            Height = 16,
            CornerRadius = new CornerRadius(8),
            Background = Brushes.Gray,
            Child = Ui.Icon(Glyphs.Close, 7, Brushes.White),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, -2, -2, 0),
            Visibility = Visibility.Hidden,
            Cursor = Cursors.Hand,
        };
        remove.MouseLeftButtonUp += (_, e) => { Shelf.Remove(path); e.Handled = true; };
        var cell = new Border
        {
            Padding = new Thickness(2, 6, 2, 6),
            CornerRadius = new CornerRadius(10),
            Background = Brushes.Transparent,
            Child = new Grid { Children = { stack, remove } },
        };
        cell.MouseEnter += (_, _) => { cell.Background = Ui.White(0.1); remove.Visibility = Visibility.Visible; };
        cell.MouseLeave += (_, _) => { cell.Background = Brushes.Transparent; remove.Visibility = Visibility.Hidden; };

        // Double-click opens; dragging out hands the original file to the drop target.
        Point? pressed = null;
        cell.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ClickCount == 2) { ShelfStore.Open(path); e.Handled = true; return; }
            pressed = e.GetPosition(cell);
        };
        cell.MouseMove += (_, e) =>
        {
            if (pressed is not { } start || e.LeftButton != MouseButtonState.Pressed) return;
            var delta = e.GetPosition(cell) - start;
            if (Math.Abs(delta.X) < 4 && Math.Abs(delta.Y) < 4) return;
            pressed = null;
            var data = new DataObject(DataFormats.FileDrop, new[] { path });
            model.IsInteracting = true;
            try { DragDrop.DoDragDrop(cell, data, DragDropEffects.Copy | DragDropEffects.Move | DragDropEffects.Link); }
            finally { model.IsInteracting = false; }
        };
        cell.MouseLeftButtonUp += (_, _) => pressed = null;

        var menu = new ContextMenu();
        menu.Items.Add(MenuItem("Open", () => ShelfStore.Open(path)));
        menu.Items.Add(MenuItem("Show in Explorer", () => ShelfStore.ShowInExplorer(path)));
        menu.Items.Add(MenuItem("Share", () => model.Share?.Invoke(new[] { path })));
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuItem("Remove from Shelf", () => Shelf.Remove(path)));
        cell.ContextMenu = menu;
        return cell;
    }

    /// Drop files here to share them (Nearby Sharing, Mail, …); click to pick files.
    private FrameworkElement ShareTarget(bool stretched)
    {
        var circle = new Border
        {
            Width = 46,
            Height = 46,
            CornerRadius = new CornerRadius(23),
            Background = Ui.White(0.1),
            Child = Ui.Icon(Glyphs.Share, 16, Ui.White(0.75)),
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        var title = Ui.Text("Share", 13, FontWeights.Bold, Ui.White(0.9));
        title.HorizontalAlignment = HorizontalAlignment.Center;
        var label = Ui.VStack(8, circle, title);
        label.VerticalAlignment = VerticalAlignment.Center;
        var card = new Border
        {
            CornerRadius = new CornerRadius(26),
            Background = Ui.White(0.06),
            Child = label,
            Width = stretched ? double.NaN : 104,
            AllowDrop = true,
        };
        void Shade(double card_, double circle_) { card.Background = Ui.White(card_); circle.Background = Ui.White(circle_); }
        card.MouseEnter += (_, _) => Shade(0.09, 0.16);
        card.MouseLeave += (_, _) => Shade(0.06, 0.1);
        card.DragEnter += (_, e) => { Shade(0.14, 0.22); e.Handled = true; };
        card.DragLeave += (_, e) => { Shade(0.06, 0.1); e.Handled = true; };
        card.DragOver += (_, e) =>
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            e.Handled = true;
        };
        card.Drop += (_, e) =>
        {
            Shade(0.06, 0.1);
            e.Handled = true;
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
                Dispatcher.BeginInvoke(() => model.Share?.Invoke(files));
        };
        return Ui.Button(card, () => model.ChooseAndShare?.Invoke());
    }
}
