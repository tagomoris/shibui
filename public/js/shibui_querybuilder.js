$(function(){
  extract_saved_items();

  $('#builder_add_cond_item').change(function(e){
    e.preventDefault();
    var target = $(e.target);
    add_cond_control_group(target.val(), target.children('option:selected').text());
    target.val('none');
  });
  $('#builder_add_result_item').change(function(e){
    e.preventDefault();
    var target = $(e.target);
    add_result_control_group(target.val(), target.children('option:selected').text());
    target.val('none');
  });

  $('#query_dumped').focus(function(e){
    var target = $(e.target);
    target.data('hasFocus', 'true');
    if (! target.hasClass('changed'))
      query_watcher(target.val());
  });
  $('#query_dumped').blur(function(e){ $(e.target).data('hasFocus', ''); });
  
  $('#execute_builder_query').click(execute_builder_query);

  rebind_events();

  start_query_updator();
});

function query_watcher(pre_value) {
  if ($('#query_dumped').val() !== pre_value) {
    $('#query_dumped').addClass('changed');
    return;
  }
  if ($('#query_dumped').data('hasFocus') === 'true') {
    pre_value = $('#query_dumped').val();
    window.setTimeout(function(){query_watcher(pre_value);}, 500);
  }
}

function rebind_events() {
  $('.cond_item_add_action').unbind().click(function(e){
    e.preventDefault();
    add_cond_item($(e.target).closest('.controls'));
    return false;
  });
  $('.result_item_add_action').unbind().click(function(e){
    e.preventDefault();
    add_result_item($(e.target).closest('.controls'));
    return false;
  });

  $('.cond_item_remove_action').unbind().click(function(e){
    e.preventDefault();
    if ($(e.target).closest('.cond_item_remove_action').hasClass('btn-inverse'))
      return false;
    var controls = $(e.target).closest('.controls'),
        target = $(e.target).closest('.cond_item');
    remove_cond_item(controls, target);
    return false;
  });
  $('.result_item_remove_action').unbind().click(function(e){
    e.preventDefault();
    if ($(e.target).closest('.result_item_remove_action').hasClass('btn-inverse'))
      return false;
    var controls = $(e.target).closest('.controls'),
        target = $(e.target).closest('.result_item');
    remove_result_item(controls, target);
    return false;
  });

  $('.cond_item_change_action').unbind().change(function(e){
    e.preventDefault();
    change_cond_item($(e.target));
    return false;
  });
  $('.result_item_change_action').unbind().change(function(e){
    e.preventDefault();
    change_result_item($(e.target));
    return false;
  });
}

function start_query_updator() {
  var param_string = '',
      wait = 1000 * 2;
  if ($('#query_dumped').val().length > 0) {
    param_string = null;
    wait = 1;
  }

  window.setTimeout(function(){
    build_query_loop(param_string);
  }, wait);
}

function extract_saved_items() {

  var prepare_saved_data = function(saved_data) {
    var group = saved_data.data('group'), type = saved_data.data('type'), num = saved_data.data('num'), val = saved_data.data('val');
    var is_cond = (group === 'condition');
    var item_name = type + num;

    var controls_selector = is_cond ? '.controls#cond_' + type : '.controls#result_' + type;
    if ($(controls_selector).size() < 1) {
      if (is_cond)
        add_cond_control_group(type, $('select#builder_add_cond_item > option[value="' + type + '"').text());
      else
        add_result_control_group(type, $('select#builder_add_result_item > option[value="' + type + '"').text());
    }
    var controls = $(controls_selector);

    var input_selector = '[name="' + item_name + '"]';
    while ($(input_selector).size() < 1) {
      if (is_cond)
        add_cond_item(controls);
      else
        add_result_item(controls);
    }

    var block = $(input_selector).closest(is_cond ? 'div.cond_item' : 'div.result_item');
    
    block.find(input_selector).val(val);
    block.find(input_selector).filter('select').each(function(){
      if (is_cond)
        change_cond_item($(this));
      else
        change_result_item($(this));
    });
    saved_data.children('select.saved_option').each(function(){
      var opt = $(this);
      block.find('[name="' + item_name + '_' + opt.data('name') + '"]').val(opt.data('val'));
      if (is_cond)
        change_cond_item(opt);
      else
        change_result_item(opt);
    });
    saved_data.children('.saved_option:not(select)').each(function(){
      var opt = $(this);
      block.find('[name="' + item_name + '_' + opt.data('name') + '"]').val(opt.data('val'));
    });
    
  };

  $('#condition_saved_data > .saved_item, #result_saved_data > .saved_item').each(function(){
    var item = $(this); prepare_saved_data(item);
  });

  if ($('#query_saved_data').size() > 0) {
    $('#query_dumped')
      .val($('#query_saved_data').data('query'));
  }
}

function execute_builder_query(event) {
  var param_string = $('form#query_structure').serialize();
  var query = $('#query_dumped').val();
  var offset_value = $('#query_offset').val();

  $('#run_query_error').text('').hide();
  $.ajax({
    type: 'POST',
    url: '/query_builder/run',
    data: {query: query, form: param_string, offset: offset_value},
    success: function(data) {
      if (data.error == 0) {
        location.href = data.location;
      }
      else {
        $('#run_query_error').text(data.message.split("\n").join('<br />')).show();
      }
    },
    error: function(err) {
      console.log(err);
      $('#run_query_error').text('error').show();
    }
  });
}

function build_query_loop(pre_param_string) {
  var targetForm = $('form#query_structure');
  if (pre_param_string === null) {
    // case when textare initialized by pre-existing query
    var existing_params = targetForm.serialize();
    $.ajax({
      type: 'POST',
      url: '/query_builder/build',
      data: existing_params,
      success: function(data) {
        if (data.query != $('#query_dumped').val()) {
          $('#query_dumped').addClass('changed');
        }
        window.setTimeout(function(){ build_query_loop(existing_params); }, 2000);
      },
      error: function(err) {
        console.log(err);
        window.setTimeout(function(){ build_query_loop(existing_params); }, 2000);
      }
    });
    return;
  }


  if (targetForm.find('input[name="service0"]').val().length < 1) {
    window.setTimeout(function(){ build_query_loop(pre_param_string); }, 1000);
    return;
  }

  var param_string = targetForm.serialize();
  if (pre_param_string === param_string) {
    window.setTimeout(function(){ build_query_loop(pre_param_string); }, 1000);
    return;
  }

  $.ajax({
    type: 'POST',
    url: '/query_builder/build',
    data: param_string,
    success: function(data) {
      $('#query_dumped')
        .val(data.query)
        .removeClass('changed');
      window.setTimeout(function(){ build_query_loop(param_string); }, 2000);
    },
    error: function(err) {
      window.setTimeout(function(){ build_query_loop(param_string); }, 2000);
    }
  });
}

function write_next_num(target, prev, type){
  var primary_name = new RegExp('^' + type + '(\\d+)$');
  var max_num = -1;
  if (prev) {
    prev.find('select,input,textarea').each(function(i,e){
      var match = primary_name.exec($(e).attr('name'));
      if (! match)
        return;
      var num = parseInt(match[1]);
      if (num > max_num)
        max_num = num;
    });
  }
  var basename = type + (max_num + 1);
  target.find('select,input,textarea').each(function(i,e){
    var tag = $(e),
        tag_name = tag.attr('name');
    if (tag_name.length < 1)
      tag.attr('name', basename);
    else
      tag.attr('name', basename + '_' + tag_name);
  });
};

function add_cond_control_group(add_type, label) {
  if ($('#cond_' + add_type).size() > 0) {
    return false;
  }
  if (add_type === 'none') {
    return false;
  }

  var control_group = $('#control_group_cond_template').clone().attr('id', null);
  var item = $('#cond_item_template_' + add_type).clone().attr('id', null);
  write_next_num(item, null, add_type);

  control_group.find('.controls').attr('id', 'cond_' + add_type);
  control_group.children('label').text(label);
  control_group.find('.controls').children().eq(0).before(item);

  $('#cond_block > fieldset').children().eq(-1).after(control_group);

  rebind_events();

  return false;
}

function add_result_control_group(add_type, label) {
  if ($('#result_' + add_type).size() > 0) {
    return false;
  }
  if (add_type === 'none') {
    return false;
  }

  var control_group = $('#control_group_result_template').clone().attr('id', null);
  var item = $('#result_item_template_' + add_type).clone().attr('id', null);
  write_next_num(item, null, add_type);

  control_group.find('.controls').attr('id', 'result_' + add_type);
  control_group.children('label').text(label);
  control_group.find('.controls').children().eq(0).before(item);

  $('#result_block > fieldset').children().eq(-1).after(control_group);

  rebind_events();

  return false;
}

function add_cond_item(controls) {
  var type = /^cond_([a-z]*)$/.exec(controls.attr('id'))[1];

  var item = $('#input_parts_warehouse > #cond_item_template_' + type).clone().attr('id', null);
  var or_parts = $('#input_parts_warehouse > .cond_item_or').clone();

  var last_item = controls.children('.cond_item').eq(-1);
  write_next_num(item, last_item, type);

  if (item.find('.cond_item_select_date').size() > 0) {
    if (controls.find('.cond_item_select_date').eq(0).val() === 'today') {
      var target = item.find('.cond_item_select_date');
      target.val('today');
      target.siblings('.hourinput').val('00').show();
      target.siblings('.dateinput').hide();
    }
  }

  last_item.css('display', 'block');
  or_parts.insertAfter(last_item);
  item.insertAfter(or_parts);

  controls.find('a.cond_item_remove_action.btn-inverse').removeClass('btn-inverse');

  rebind_events();

  return false;
}

function add_result_item(controls) {
  var type = /^result_([a-z]*)$/.exec(controls.attr('id'))[1];

  var item = $('#input_parts_warehouse > #result_item_template_' + type).clone().attr('id', null);

  var last_item = $('div.controls#result_' + type).children('.result_item').eq(-1);
  write_next_num(item, last_item, type);

  last_item.css('display', 'block');
  item.insertAfter(last_item);

  controls.find('a.result_item_remove_action.btn-inverse').removeClass('btn-inverse');

  rebind_events();

  return false;
}

function remove_cond_item(controls, target) {
  var type = /^cond_([a-z]*)$/.exec(controls.attr('id'))[1];

  if (controls.children('.cond_item').size() < 2) {
    controls.closest('.control-group').remove();
    return false;
  }
  var cond_items = controls.children('.cond_item');
  if (target.is(cond_items.eq(-1))) {
    cond_items.eq(-2).css('display', 'inline');
    controls.children('.cond_item_or').eq(-1).remove();
    target.remove();
  }
  else {
    target.next('.cond_item_or').remove();
    target.remove();
  }

  var normal_pattern = new RegExp('^' + type + '\\d+$');
  var ex_pattern = new RegExp('^' + type + '\\d+(_[^_]+)$');
  $('#cond_' + type).children('.cond_item').each(function(index,element){
    $(element).find('select,input,textarea').each(function(i,e){
      var name = $(e).attr('name');
      if (name === '' || normal_pattern.exec(name)) {
        $(e).attr('name', type + index);
      }
      else if (ex_pattern.exec(name)) {
        var match = ex_pattern.exec(name);
        $(e).attr('name', type + index + match[1]);
      }
      else {
        $(e).attr('name', type + index + '_' + name);
      }
    });
  });

  if (type === 'service' || type === 'date') {
    if (controls.find('a.cond_item_remove_action').size() < 2) {
      controls.find('a.cond_item_remove_action').addClass('btn-inverse');
    }
  }

  return false;
}

function remove_result_item(controls, target) {
  var type = /^result_([a-z]*)$/.exec(controls.attr('id'))[1];

  if (controls.children('.result_item').size() < 2) {
    controls.closest('.control-group').remove();
    return false;
  }
  var result_items = controls.children('.result_item');
  if (target.is(result_items.eq(-1))) {
    result_items.eq(-2).css('display', 'inline');
  }
  target.remove();

  var normal_pattern = new RegExp('^' + type + '\\d+$');
  var ex_pattern = new RegExp('^' + type + '\\d+(_[^_]+)$');
  $('#result_' + type).children('.result_item').each(function(index,element){
    $(element).find('select,input,textarea').each(function(i,e){
      var name = $(e).attr('name');
      if (name === '' || normal_pattern.exec(name)) {
        $(e).attr('name', type + index);
      }
      else if (ex_pattern.exec(name)) {
        var match = ex_pattern.exec(name);
        $(e).attr('name', type + index + match[1]);
      }
      else {
        $(e).attr('name', type + index + '_' + name);
      }
    });
  });

  if (type === 'rdate') {
    if (controls.find('a.result_item_remove_action').size() < 2) {
      controls.find('a.result_item_remove_action').addClass('btn-inverse');
    }
  }

  return false;
}

function change_cond_item(target) {
  if (target.hasClass('cond_item_select_date')) {
    if (target.val() === 'today') {
      target.siblings('.hourinput').val('00').show();
      target.siblings('.dateinput').hide();
    }
    else if (target.val() === 'specified') {
      target.siblings('.hourinput').val('').hide();
      target.siblings('.dateinput').show();
    }
    else {
      target.siblings('.hourinput,.dateinput').val('').hide();
    }
  }

  return false;
}

function change_result_item(target) {
  if (target.hasClass('result_item_select_date')) {
    if (target.val() === 'select') {
      target.siblings('.dateoption').show();
    }
    else {
      target.siblings('.dateoption').hide();
    }
  }
  else if (target.hasClass('result_item_select_fieldtype')) {
    target.siblings('.timeoption,.requestoption,.responseoption,.userinfooption').hide();
    switch (target.val()) {
    case 'time':
      target.siblings('.timeoption').show();
      break;
    case 'request':
      target.siblings('.requestoption').show();
      break;
    case 'response':
      target.siblings('.responseoption').show();
      break;
    case 'userinfo':
      target.siblings('.userinfooption').show();
      break;
    }
  }
  else if (target.hasClass('result_item_select_aggregates')) {
    if (target.val() === 'count' || target.val() === 'uucount') {
      target.siblings('.countoption').show();
      target.siblings('.numaggroption').hide();
    } else {
      target.siblings('.countoption').hide();
      target.siblings('.numaggroption').show();
    }
  }
  else if (target.hasClass('result_item_select_countoption')) {
    if (target.val() === 'path' || target.val() === 'vhost' || target.val() === 'referer') {
      target.siblings('.countextoption').show();
      target.siblings('.countextoption').find('select').val('equal');
      target.siblings('.countextoption').find('input').val('');
    }
    else {
      target.siblings('.countextoption').hide();
    }
  }

  return false;
}
