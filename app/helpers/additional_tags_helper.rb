require 'digest/md5'

module AdditionalTagsHelper
  include ActsAsTaggableOn::TagsHelper

  def manageable_tags
    AdditionalTags::Tags.sort_tag_list ActsAsTaggableOn::Tag.where({})
  end

  def manageable_tag_columns
    return @manageable_tag_columns if defined? @manageable_tag_columns

    columns = {}

    if AdditionalTags.setting?(:active_issue_tags)
      columns[:issue] = { label: l(:label_issue_plural),
                          tag_controller: :issues,
                          counts: Issue.available_tags.map { |tag| [tag.id, tag.count] }.to_h }
    end

    if AdditionalTags.setting?(:active_wiki_tags)
      columns[:wiki] = { label: l(:label_wiki),
                         counts: WikiPage.available_tags.map { |tag| [tag.id, tag.count] }.to_h }
    end

    call_hook :helper_additional_manageable_tag_columns, columns: columns

    @manageable_tag_columns = columns
  end

  def manageable_tag_column_values(tag)
    columns = []
    manageable_tag_columns.each do |_column, column_values|
      cnt = column_values[:counts][tag.id]
      cnt = 0 if cnt.blank?

      columns << if cnt.positive? && column_values[:tag_controller]
                   link_to cnt, tag_url(tag.name, tag_controller: column_values[:tag_controller])
                 else
                   cnt
                 end
    end
    columns
  end

  def render_tags_list(tags, options = {})
    return if tags.blank?

    style = options.delete(:style)
    tags = tags.all.to_a if tags.respond_to?(:all)

    case "#{AdditionalTags.setting :tags_sort_by}:#{AdditionalTags.setting :tags_sort_order}"
    when 'name:desc'
      tags = AdditionalTags::Tags.sort_tag_list(tags).reverse
    when 'count:asc'
      tags.sort! { |a, b| a.count <=> b.count }
    when 'count:desc'
      tags.sort! { |a, b| b.count <=> a.count }
    else
      tags = AdditionalTags::Tags.sort_tag_list tags
    end

    case style
    when :list
      list_el = 'ul'
      item_el = 'li'
    when :simple_cloud, :cloud
      list_el = 'div'
      item_el = 'span'
    else
      raise 'Unknown list style'
    end

    content = ''.html_safe
    if style == :list && AdditionalTags.setting(:tags_sort_by) == 'name'
      tags.group_by { |tag| tag.name.downcase.first }.each do |letter, grouped_tags|
        content << content_tag(item_el, letter.upcase, class: 'letter')
        add_tags style, grouped_tags, content, item_el, options
      end
    else
      add_tags style, tags, content, item_el, options
    end

    content_tag(list_el, content, class: 'tags-cloud', style: (style == :simple_cloud ? 'text-align: left;' : ''))
  end

  def additional_tag_link(tag_object, options = {})
    tag_name = []
    tag_name << tag_object.name

    options[:project] = @project if options[:project].blank? && @project.present?

    use_colors = AdditionalTags.setting?(:use_colors)
    if use_colors
      tag_bg_color = additional_tag_color tag_object.name
      tag_fg_color = additional_tag_fg_color tag_bg_color
      tag_style = "background-color: #{tag_bg_color}; color: #{tag_fg_color}"
    end

    tag_name << tag.span("(#{tag_object.count})", class: 'tag-count') if options[:show_count]

    content = if options[:link]
                link_to safe_join(tag_name),
                        options[:link],
                        style: tag_style
              elsif options[:link_wiki_tag]
                link_to safe_join(tag_name),
                        project_wiki_index_path(options[:project], tag: tag_object.name),
                        style: tag_style
              else
                link_to safe_join(tag_name),
                        tag_url(tag_object.name, options),
                        style: tag_style
              end

    style = if use_colors
              { class: 'additional-tag-label-color', style: tag_style }
            else
              { class: 'tag-label' }
            end

    tag.span content, style
  end

  def additional_tag_color(tag_name)
    "##{Digest::MD5.hexdigest(tag_name)[0..5]}"
  end

  def additional_tag_fg_color(bg_color)
    # calculate contrast text color according to YIQ method
    # https://24ways.org/2010/calculating-color-contrast/
    # https://stackoverflow.com/questions/3942878/how-to-decide-font-color-in-white-or-black-depending-on-background-color
    r = bg_color[1..2].hex
    g = bg_color[3..4].hex
    b = bg_color[5..6].hex
    (r * 299 + g * 587 + b * 114) >= 128_000 ? 'black' : 'white'
  end

  # plain list of tags
  def additional_plain_tag_list(tags, sep = ' ')
    s = if tags.blank?
          ['']
        else
          tags.map(&:name)
        end
    s.join sep
  end

  def additional_tag_links(tag_list, options = {})
    return if tag_list.blank?

    sep = if options[:use_colors].nil? || options[:use_colors]
            ' '
          else
            ', '
          end

    unsorted = options.delete(:unsorted)
    tag_list = AdditionalTags::Tags.sort_tag_list(tag_list) unless unsorted

    safe_join tag_list.map { |tag| additional_tag_link tag, options }, sep
  end

  private

  def tag_url(tag_name, options = {})
    action = options[:tag_action].presence || (controller_name == 'hrm_user_resources' ? 'show' : 'index')

    fields = [:tags]
    values = { tags: [tag_name] }
    operators = { tags: '=' }

    if options[:filter].present?
      field = options[:filter][:field]
      fields << field
      operators[field] = options[:filter][:operator]
      values[field] = options[:filter][:value] if options[:filter].key?(:value)
    end

    { controller: options[:tag_controller].presence || controller_name,
      action: action,
      set_filter: 1,
      project_id: options[:project],
      f: fields,
      v: values,
      op: operators }
  end

  def add_tags(style, tags, content, item_el, options)
    tag_cloud tags, (1..8).to_a do |tag, weight|
      content << ' '.html_safe + content_tag(item_el,
                                             additional_tag_link(tag, options),
                                             class: "tag-nube-#{weight}",
                                             style: (style == :simple_cloud ? 'font-size: 1em;' : '')) + ' '.html_safe
    end
  end
end
