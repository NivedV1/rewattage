/* chart-drawer.vala
 *
 * Copyright 2025 v81d
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

using Gee;
using DeviceManager;

namespace Wattage {
  internal struct HistoryPoint {
    public int64 time;
    public double value;
    public uint state;
    public bool starts_segment;

    public HistoryPoint (int64 time, double value, uint state, bool starts_segment) {
      this.time = time;
      this.value = value;
      this.state = state;
      this.starts_segment = starts_segment;
    }
  }

  internal enum HistoryMetric {
    PERCENTAGE,
    RATE
  }

  internal class HistoryChart : Gtk.Box {
    private const int MIN_LEFT_PADDING = 42;
    private const int RIGHT_PADDING = 8;
    private const int TOP_PADDING = 9;
    private const int BOTTOM_PADDING = 26;

    private HistoryMetric metric;
    private string unit;
    private Adw.AccentColor accent;
    private Gtk.Label latest;
    private Gtk.DrawingArea graph;
    private Gtk.Stack plot;
    private Gtk.Label unavailable;
    private Gtk.MenuButton entries_button;
    private Gtk.Popover entries;
    private Gtk.StringList readings = new Gtk.StringList (null);

    private ArrayList<HistoryPoint?> points = new ArrayList<HistoryPoint?> ();
    private int64 start;
    private int64 end;
    private double axis_min;
    private double axis_max;
    private double tick_step;
    private double left_padding;
    private int hovered = -1;

    public HistoryChart (HistoryMetric metric, string title, string unit, Adw.AccentColor accent) {
      Object (orientation: Gtk.Orientation.VERTICAL, spacing: 6,
        margin_start: 1, margin_end: 1);
      this.metric = metric;
      this.unit = unit;
      this.accent = accent;
      this.add_css_class ("card");

      var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
        margin_start = 14, margin_end = 12, margin_top = 7
      };
      var label = new Gtk.Label (title) { xalign = 0, hexpand = true, wrap = true };
      label.add_css_class ("heading");
      header.append (label);

      this.latest = new Gtk.Label ("—");
      this.latest.add_css_class ("title-2");
      this.latest.add_css_class ("numeric");
      header.append (this.latest);

      this.entries_button = new Gtk.MenuButton () {
        icon_name = "view-list-symbolic",
        tooltip_text = _("Entries"),
        valign = Gtk.Align.CENTER,
        sensitive = false
      };
      this.entries_button.add_css_class ("flat");
      header.append (this.entries_button);
      this.append (header);
      this.initialize_entries ();

      this.plot = new Gtk.Stack () {
        margin_start = 13, margin_end = 13, margin_bottom = 5
      };
      this.graph = new Gtk.DrawingArea () {
        content_height = metric == HistoryMetric.PERCENTAGE ? 152 : 134,
        has_tooltip = true
      };
      this.graph.update_relation (Gtk.AccessibleRelation.LABELLED_BY, label, null);
      this.graph.set_draw_func (draw_chart);
      this.graph.query_tooltip.connect (this.show_tooltip);

      var pointer = new Gtk.EventControllerMotion ();
      pointer.motion.connect (this.highlight_point);
      pointer.leave.connect (this.clear_highlight);
      this.graph.add_controller (pointer);
      this.plot.add_named (this.graph, "graph");

      var spinner = new Adw.Spinner () { halign = Gtk.Align.CENTER, valign = Gtk.Align.CENTER };
      this.plot.add_named (spinner, "loading");
      this.unavailable = new Gtk.Label (null) {
        wrap = true, justify = Gtk.Justification.CENTER
      };
      this.unavailable.add_css_class ("dim-label");
      this.plot.add_named (this.unavailable, "unavailable");
      this.append (this.plot);
    }

    private void initialize_entries () {
      var factory = new Gtk.SignalListItemFactory ();
      factory.setup.connect ((object) => {
        var label = new Gtk.Label (null) {
          xalign = 0, wrap = true, margin_top = 6, margin_bottom = 6,
          margin_start = 9, margin_end = 9
        };
        ((Gtk.ListItem) object).child = label;
      });
      factory.bind.connect ((object) => {
        var item = (Gtk.ListItem) object;
        ((Gtk.Label) item.child).label = ((Gtk.StringObject) item.item).string;
      });

      var list = new Gtk.ListView (new Gtk.NoSelection (this.readings), factory);
      var scroll = new Gtk.ScrolledWindow () {
        hscrollbar_policy = Gtk.PolicyType.NEVER,
        min_content_width = 210,
        max_content_height = 280,
        propagate_natural_height = true,
        child = list
      };
      this.entries = new Gtk.Popover () { child = scroll };
      this.entries.show.connect (this.update_entries);
      this.entries_button.popover = this.entries;
    }

    private void update_entries () {
      string[] rows = new string[this.points.size];
      for (int i = 0; i < rows.length; i++) {
        rows[i] = this.describe (this.points.get (rows.length - 1 - i));
      }
      this.readings.splice (0, this.readings.get_n_items (), rows);
    }

    public void show_loading () {
      this.points.clear ();
      this.latest.label = "—";
      this.entries_button.sensitive = false;
      this.entries.popdown ();
      this.plot.visible_child_name = "loading";
    }

    public void show_unavailable () {
      this.show_series (new ArrayList<HistoryPoint?> (), 0, 0);
      this.unavailable.label = _("History Unavailable");
    }

    public void show_series (ArrayList<HistoryPoint?> points, int64 start, int64 end) {
      this.points = points;
      this.start = start;
      this.end = end;
      this.hovered = -1;
      bool available = !points.is_empty;
      this.latest.label = available ? this.format_value (points.get (points.size - 1).value) : "—";
      this.entries_button.sensitive = available;
      if (this.entries.visible)
        this.update_entries ();

      this.unavailable.label = available ? "" :
        _("No history entries available within the configured timespan and resolution.");
      this.plot.visible_child_name = available ? "graph" : "unavailable";
      if (available) {
        this.scale_axis ();
        this.graph.queue_draw ();
      }
    }

    private string format_value (double value) {
      if (this.metric == HistoryMetric.PERCENTAGE)
        return "%.1f%%".printf (value);

      double magnitude = value.abs ();
      if (magnitude != 0 && (magnitude < 0.1 || magnitude >= 10000))
        return "%.3g %s".printf (value, this.unit);
      return "%.1f %s".printf (value, this.unit);
    }

    private string describe (HistoryPoint point) {
      var timestamp = new DateTime.from_unix_local (point.time);
      string value = this.format_value (point.value);
      string? state = DeviceProber.stringify_device_state (point.state);
      if (state != null)
        value = "%s · %s".printf (value, state);

      return "%s\n%s".printf (timestamp.format ("%c"), value);
    }

    private void scale_axis () {
      if (this.metric == HistoryMetric.PERCENTAGE) {
        this.axis_min = 0;
        this.axis_max = 100;
        this.tick_step = 25;
        return;
      }

      double min = this.points.get (0).value;
      double max = min;
      foreach (HistoryPoint point in this.points) {
        min = double.min (min, point.value);
        max = double.max (max, point.value);
      }

      min = double.min (0, min);
      max = double.max (0, max);
      double rough_step = (max - min) / 4;
      if (rough_step == 0)
        rough_step = 0.25;

      double power_of_ten = Math.pow (10, Math.floor (Math.log10 (rough_step)));
      double fraction = rough_step / power_of_ten;
      this.tick_step = power_of_ten * (fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10);
      this.axis_min = Math.floor (min / this.tick_step) * this.tick_step;
      this.axis_max = Math.ceil (max / this.tick_step) * this.tick_step;
      if (this.axis_max == this.axis_min)
        this.axis_max += 4 * this.tick_step;
    }

    private double x_position (int64 time, double right) {
      return this.left_padding + (double) (time - this.start) / (this.end - this.start) *
        (right - this.left_padding);
    }

    private double y_position (double value, double bottom) {
      return bottom - (value - this.axis_min) / (this.axis_max - this.axis_min) *
        (bottom - TOP_PADDING);
    }

    private int point_at (double x, double y) {
      double right = this.graph.get_width () - RIGHT_PADDING;
      if (x < this.left_padding - 4 || x > right + 4 ||
        y < 0 || y > this.graph.get_height () - BOTTOM_PADDING + 4)
        return -1;

      int nearest = -1;
      double distance = 24;
      for (int i = 0; i < this.points.size; i++) {
        double delta = (x - this.x_position (this.points.get (i).time, right)).abs ();
        if (delta <= distance) {
          distance = delta;
          nearest = i;
        }
      }
      return nearest;
    }

    private void highlight_point (double x, double y) {
      int index = this.point_at (x, y);
      if (index != this.hovered) {
        this.hovered = index;
        this.graph.queue_draw ();
      }
    }

    private void clear_highlight () {
      this.hovered = -1;
      this.graph.queue_draw ();
    }

    private bool show_tooltip (int x, int y, bool keyboard, Gtk.Tooltip tooltip) {
      int index = this.point_at (x, y);
      if (keyboard || index == -1)
        return false;

      tooltip.set_text (this.describe (this.points.get (index)));
      return true;
    }

    private static void draw_chart (Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
      var card = area.get_ancestor (typeof (HistoryChart)) as HistoryChart;
      card?.draw (cr, width, height);
    }

    private void draw (Cairo.Context cr, int width, int height) {
      if (this.points.is_empty)
        return;

      var layout = this.graph.create_pango_layout (null);
      var attributes = new Pango.AttrList ();
      attributes.insert (Pango.attr_scale_new (0.85));
      layout.set_attributes (attributes);

      var y_labels = new ArrayList<string> ();
      int tick_count = (int) Math.round ((this.axis_max - this.axis_min) / this.tick_step);
      this.left_padding = MIN_LEFT_PADDING;
      for (int tick = 0; tick <= tick_count; tick++) {
        double value = this.axis_min + tick * this.tick_step;
        if (value.abs () < this.tick_step * 1e-6)
          value = 0;
        string text = this.metric == HistoryMetric.PERCENTAGE ?
          "%.0f%%".printf (value) : "%.4g".printf (value);
        y_labels.add (text);
        layout.set_text (text, -1);
        int label_width;
        layout.get_pixel_size (out label_width, null);
        this.left_padding = double.max (this.left_padding, label_width + 10);
      }

      double right = width - RIGHT_PADDING;
      double bottom = height - BOTTOM_PADDING;
      if (right <= this.left_padding || bottom <= TOP_PADDING)
        return;

      Gdk.RGBA ink = this.graph.get_color ();
      cr.set_line_width (1);
      for (int tick = 0; tick <= tick_count; tick++) {
        double value = this.axis_min + tick * this.tick_step;
        double y = this.y_position (value, bottom);
        double opacity = value.abs () < this.tick_step * 1e-6 ? 0.24 : 0.12;

        cr.set_source_rgba (ink.red, ink.green, ink.blue, opacity);
        cr.move_to (this.left_padding, y);
        cr.line_to (right, y);
        cr.stroke ();

        layout.set_text (y_labels.get (tick), -1);
        int label_height;
        layout.get_pixel_size (null, out label_height);
        cr.set_source_rgba (ink.red, ink.green, ink.blue, 0.75);
        cr.move_to (0, y - label_height / 2.0);
        Pango.cairo_show_layout (cr, layout);
      }

      var first_day = new DateTime.from_unix_local (this.start);
      var last_day = new DateTime.from_unix_local (this.end);
      bool spans_days = first_day.get_day_of_year () != last_day.get_day_of_year () ||
        first_day.get_year () != last_day.get_year ();
      bool use_dates = this.end - this.start > 24 * 60 * 60;
      int x_intervals = width >= 430 ? 4 : width >= 245 ? 2 : 1;
      for (int tick = 0; tick <= x_intervals; tick++) {
        int64 time = this.start + (this.end - this.start) * tick / x_intervals;
        double x = this.x_position (time, right);

        cr.set_source_rgba (ink.red, ink.green, ink.blue, 0.12);
        cr.move_to (x, TOP_PADDING);
        cr.line_to (x, bottom);
        cr.stroke ();

        var date = new DateTime.from_unix_local (time);
        bool endpoint = tick == 0 || tick == x_intervals;
        string format = use_dates ? "%b %d" : spans_days && endpoint ? "%b %d %H:%M" : "%H:%M";
        layout.set_text (date.format (format), -1);
        int label_width;
        layout.get_pixel_size (out label_width, null);
        cr.set_source_rgba (ink.red, ink.green, ink.blue, 0.75);
        cr.move_to ((x - label_width / 2.0).clamp (0, int.max (0, width - label_width)), bottom + 6);
        Pango.cairo_show_layout (cr, layout);
      }

      Gdk.RGBA color = this.accent.to_standalone_rgba (Adw.StyleManager.get_default ().dark);
      this.draw_series (cr, color, right, bottom);
    }

    private void draw_series (Cairo.Context cr, Gdk.RGBA color, double right, double bottom) {
      cr.save ();
      cr.rectangle (this.left_padding - 4, TOP_PADDING - 4,
        right - this.left_padding + 8, bottom - TOP_PADDING + 8);
      cr.clip ();

      double baseline = this.y_position (0.0.clamp (this.axis_min, this.axis_max), bottom);
      var fill = new Cairo.Pattern.linear (0, TOP_PADDING, 0, bottom);
      fill.add_color_stop_rgba (0, color.red, color.green, color.blue, 0.24);
      fill.add_color_stop_rgba (1, color.red, color.green, color.blue, 0.07);
      cr.set_line_width (2);
      cr.set_line_cap (Cairo.LineCap.ROUND);
      cr.set_line_join (Cairo.LineJoin.ROUND);

      int first = 0;
      while (first < this.points.size) {
        int next = first + 1;
        while (next < this.points.size && !this.points.get (next).starts_segment)
          next++;

        if (next - first > 1) {
          this.trace (cr, first, next, right, bottom);
          cr.line_to (this.x_position (this.points.get (next - 1).time, right), baseline);
          cr.line_to (this.x_position (this.points.get (first).time, right), baseline);
          cr.close_path ();
          cr.set_source (fill);
          cr.fill ();

          this.trace (cr, first, next, right, bottom);
          cr.set_source_rgba (color.red, color.green, color.blue, 1);
          cr.stroke ();
        }
        if (next - first == 1 || next == this.points.size)
          this.draw_marker (cr, next - 1, color, right, bottom, 3);
        first = next;
      }

      if (this.hovered >= 0) {
        double x = this.x_position (this.points.get (this.hovered).time, right);
        cr.set_source_rgba (color.red, color.green, color.blue, 0.5);
        cr.set_line_width (1);
        cr.move_to (x, TOP_PADDING);
        cr.line_to (x, bottom);
        cr.stroke ();
        this.draw_marker (cr, this.hovered, color, right, bottom, 4.5);
      }
      cr.restore ();
    }

    private void trace (Cairo.Context cr, int first, int next, double right, double bottom) {
      HistoryPoint initial = this.points.get (first);
      cr.move_to (this.x_position (initial.time, right), this.y_position (initial.value, bottom));
      for (int i = first + 1; i < next; i++) {
        HistoryPoint point = this.points.get (i);
        cr.line_to (this.x_position (point.time, right), this.y_position (point.value, bottom));
      }
    }

    private void draw_marker (Cairo.Context cr, int index, Gdk.RGBA color,
      double right, double bottom, double radius) {
      HistoryPoint point = this.points.get (index);
      cr.set_source_rgba (color.red, color.green, color.blue, 1);
      cr.arc (this.x_position (point.time, right), this.y_position (point.value, bottom),
        radius, 0, 2 * Math.PI);
      cr.fill ();
    }
  }
}
