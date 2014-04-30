define 'app/views', ['underscore', 'backbone', 'backbone.marionette', 'leaflet', 'i18next', 'TweenLite', 'app/p13n', 'app/widgets', 'app/jade', 'app/models', 'app/search'], (_, Backbone, Marionette, Leaflet, i18n, TweenLite, p13n, widgets, jade, models, search) ->
    service_colors =
        # tree_id: "color"
        # Housing and environment
        1: "rgb(77,139,0)"
        # Administration and economy
        3: "rgb(192,79,220)"
        # Maps, information services and communication
        5: "rgb(154,0,0)"
        # Traffic
        7: "rgb(154,0,0)"
        # Culture and leisure
        6: "rgb(252,173,0)"
        # Legal protection and democracy
        10: "rgb(192,79,220)"
        # Planning, real estate and construction
        4: "rgb(40,40,40)"
        # Tourism and events
        9: "rgb(252,172,0)"
        # Entrepreneurship, work and taxation
        2: "rgb(192,79,220)"
        # Sports and physical exercise
        8: "rgb(252,173,0)"
        # Teaching and education
        11: "rgb(0,81,142)"
        # Family and social services
        12: "rgb(67,48,64)"
        # Child daycare and pre-school education
        13: "rgb(60,210,0)"
        # Health care
        14: "rgb(142,139,255)"
        # Public safety
        15: "rgb(240,66,0)"

    class SMItemView extends Marionette.ItemView
        templateHelpers:
            t: i18n.t
        getTemplate: ->
            return jade.get_template @template

    class AppView extends Backbone.View
        initialize: (options)->
            @service_sidebar = new ServiceSidebarView
                parent: this
                service_tree_collection: options.service_list
            options.map_view.addControl 'sidebar', @service_sidebar.map_control()
            @map = options.map_view.map
            @current_markers = {}

        render: ->
            return this
        remember_markers: (service_id, markers) ->
            @current_markers[service_id] = markers
        remove_service_points: (service_id) ->
            _.each @current_markers[service_id], (marker) =>
                @map.removeLayer marker
            delete @current_markers[service_id]

        add_service_points: (service) ->
            unit_list = new models.UnitList()
            unit_list.fetch
                data:
                    service: service.id
                    page_size: 1000
                    only: 'name,location'
                success: =>
                    markers = @draw_units unit_list,
                        service: service
                    @remember_markers service.id, markers

        draw_units: (unit_list, opts) ->
            markers = []
            if opts.service?
                color = service_colors[opts.service.attributes.tree_id]
            else
                console.log "Warning: no service color"
                color = 'rgb(255,255,255)'

            unit_list.each (unit) =>
                #color = ptype_to_color[unit.provider_type]
                icon = new widgets.CanvasIcon 50, color
                location = unit.get('location')
                if location?
                    coords = location.coordinates
                    popup = L.popup(closeButton: false).setContent "<strong>#{unit.get_text 'name'}</strong>"
                    marker = L.marker([coords[1], coords[0]], icon: icon)
                        .bindPopup(popup)
                        .addTo(@map)

                    marker.unit = unit
                    unit.marker = marker
                    markers.push marker
                    marker.on 'click', (event) =>
                        marker = event.target
                        @service_sidebar.show_details marker.unit

            bounds = L.latLngBounds (m.getLatLng() for m in markers)
            bounds = bounds.pad 0.05
            # FIXME: map.fitBounds() maybe?
            if opts? and opts.zoom and unit_list.length == 1
                coords = unit_list.first().get('location').coordinates
                @map.setView [coords[1], coords[0]], 12

            return markers

        # The transitions triggered by removing the class landing from body are defined
        # in the file landing-page.less.
        # When key animations have ended a 'landing-page-cleared' event is triggered.
        clear_landing_page: () ->
            if $('body').hasClass('landing')
                $('body').removeClass('landing')
                $('.service-sidebar').on('transitionend webkitTransitionEnd oTransitionEnd MSTransitionEnd', (event) ->
                    if event.originalEvent.propertyName is 'top'
                        app.vent.trigger('landing-page-cleared')
                        $(@).off('transitionend webkitTransitionEnd oTransitionEnd MSTransitionEnd')
                )


    class ServiceSidebarView extends Backbone.View
        tagName: 'div'
        className: 'service-sidebar'
        events:
            'typeahead:selected': 'autosuggest_show_details'
            'click .header': 'open'
            'click .close-button': 'close'

        initialize: (options) ->
            @parent = options.parent
            @service_tree_collection = options.service_tree_collection
            @render()

        map_control: ->
            return new widgets.ServiceSidebarControl @el

        switch_content: (content_type) ->
            classes = "container #{ content_type }-open"
            @$el.find('.container').removeClass().addClass(classes)

        open: (event) ->
            event.preventDefault()
            if @prevent_switch
                @prevent_switch = false
                return
            $element = $(event.currentTarget)
            type = $element.data('type')

            # Select all text when search is opened.
            if type is 'search'
                @$el.find('input').select()

            @switch_content type
            @parent.clear_landing_page()

        close: (event) ->
            event.preventDefault()
            event.stopPropagation()
            $('.service-sidebar .container').removeClass().addClass('container')

            type = $(event.target).closest('.header').data('type')
            # Clear search query if search is closed.
            if type is 'search'
                @$el.find('input').val('')

        autosuggest_show_details: (ev, data, _) ->
            @prevent_switch = true
            if data.object_type == 'unit'
                @show_details new models.Unit(data),
                    zoom: true
                    draw_marker: true
            else if data.object_type == 'service'
                @switch_content 'browse'
                @service_tree.show_service(new models.Service(data))

        show_details: (unit, opts) ->
            if not opts
                opts = {}

            @$el.find('.container').addClass('details-open')
            @details_view.model = unit
            unit.fetch(success: =>
                @details_view.render()
            )
            @details_view.render()
            if opts.draw_marker
                unit_list = new models.UnitList [unit]
                @parent.draw_units unit_list, opts

            # Set for console access
            window.debug_unit = unit

        hide_details: ->
            @$el.find('.container').removeClass('details-open')

        enable_typeahead: (selector) ->
            @$el.find(selector).typeahead null,
                source: search.engine.ttAdapter(),
                displayKey: (c) -> c.name[p13n.get_language()],
                templates:
                    empty: (ctx) -> jade.template 'typeahead-no-results', ctx
                    suggestion: (ctx) -> jade.template 'typeahead-suggestion', ctx

        render: ->
            s1 = i18n.t 'sidebar.search'
            if not s1
                console.log i18n
                throw 'i18n not initialized'
            template_string = jade.template 'service-sidebar'
            @el.innerHTML = template_string
            @enable_typeahead('input.form-control[type=search]')

            @service_tree = new ServiceTreeView
                collection: @service_tree_collection
                app_view: @parent
                el: @$el.find('#service-tree-container')

            @details_view = new DetailsView
                el: @$el.find('#details-view-container')
                parent: @
                model: new models.Unit()

            return @el


    class DetailsView extends Backbone.View
        events:
            'click .back-button': 'close'

        initialize: (options) ->
            @parent = options.parent

        close: (event) ->
            event.preventDefault()
            @parent.hide_details()

        set_max_height: () ->
            # Set the details view content max height for proper scrolling.
            max_height = $(window).innerHeight() - @$el.find('.content').offset().top
            @$el.find('.content').css 'max-height': max_height

        render: ->
            data = @model.toJSON()
            template_string = jade.template 'details', data
            @el.innerHTML = template_string
            @set_max_height()

            return @el


    class ServiceTreeView extends Backbone.View
        events:
            'click .service.has-children': 'open'
            'click .service.parent': 'open'
            'click .service.leaf': 'toggle_leaf'
            'click .service .show-button': 'toggle_button'

        initialize: (options) ->
            @app_view = options.app_view
            @showing = {}
            @slide_direction = 'left'
            @listenTo @collection, 'sync', @render
            @collection.fetch
                data:
                    level: 0
            app.vent.on('landing-page-cleared', @set_max_height)

        category_url: (id) ->
            '/#/service/' + id

        toggle_leaf: (event) ->
            @toggle_element($(event.currentTarget).find('.show-button'))

        toggle_button: (event) ->
            event.preventDefault()
            @toggle_element($(event.target))
            event.stopPropagation()

        show_service: (service) =>
            @collection.expand service.attributes.parent
            @service_to_display = service

        toggle_element: ($target_element) ->
            service_id = $target_element.parent().data('service-id')
            if not @showing[service_id] == true
                $target_element.addClass 'selected'
                $target_element.text i18n.t 'sidebar.hide'
                @showing[service_id] = true
                service = new models.Service id: service_id
                service.fetch
                    success: =>
                        @app_view.add_service_points(service)
            else
                delete @showing[service_id]
                $target_element.removeClass 'selected'
                $target_element.text i18n.t 'sidebar.show'
                @app_view.remove_service_points(service_id)

        open: (event) ->
            service_id = $(event.currentTarget).data('service-id')
            @slide_direction = $(event.currentTarget).data('slide-direction')
            if not service_id
                return null
            if service_id == 'root'
                service_id = null
            @collection.expand service_id

        set_max_height: () =>
            # Set the service tree max height for proper scrolling.
            max_height = $(window).innerHeight() - @$el.offset().top
            @$el.find('.service-tree').css 'max-height': max_height

        render: ->
            classes = (category) ->
                if category.attributes.children.length > 0
                    return ['service has-children']
                else
                    return ['service leaf']

            list_items = @collection.map (category) =>
                id: category.get 'id'
                name: category.get_text 'name'
                classes: classes(category).join " "
                has_children: category.attributes.children.length > 0
                selected: @showing[category.attributes.id]

            if not @collection.chosen_service
                heading = ''
                back = null
            else
                if @collection.chosen_service
                    heading = @collection.chosen_service.get_text 'name'
                    back = @collection.chosen_service.get('parent') or 'root'
                else
                    back = null
            data =
                heading: heading
                back: back
                list_items: list_items
            template_string = jade.template 'service-tree', data

            $old_content = @$el.find('ul')
            if $old_content.length
                # Add content with sliding animation
                @$el.append $(template_string)
                $new_content = @$el.find('.new-content')

                # Calculate how much the new content needs to be moved.
                content_width = $new_content.width()
                content_margin = parseInt($new_content.css('margin-left').replace('px', ''))
                move_distance = content_width + content_margin

                if @slide_direction is 'left'
                    move_distance = "-=#{move_distance}px"
                else
                    move_distance = "+=#{move_distance}px"
                    # Move new content to the left side of the old content
                    $new_content.css 'left': -2 * (content_width + content_margin)

                TweenLite.to([$old_content, $new_content], 0.3, {
                    left: move_distance,
                    ease: Power2.easeOut,
                    onComplete: () ->
                        $old_content.remove()
                        $new_content.css 'left': 0
                        $new_content.removeClass('new-content')
                })

            else
                # Don't use animations if there is no old content
                @$el.append $(template_string)

            if @service_to_display
                $target_element = @$el.find("[data-service-id=#{@service_to_display.id}]").find('.show-button')
                @service_to_display = false
                @toggle_element($target_element)

            @set_max_height()

            return @el


    exports =
        AppView: AppView
        ServiceSidebarView: ServiceSidebarView
        ServiceTreeView: ServiceTreeView

    return exports
