function setXhrpost() {
  var myform = this;
  $(myform).first().prepend('<div class="alert alert-error hide">System Error!</div>');
  $(myform).submit(function(e){
    $(myform).find('.alert-error').hide();
    $(myform).find('.validator_message').detach();
    $(myform).find('.control-group').removeClass('error');
    $.ajax({
      type: 'POST',
      url: myform.action,
      data: $(myform).serialize(),
      success: function(data) {
        $(myform).find('.alert-error').hide();
        if ( data.error == 0 ) {
          if ($('#silent_submit').val() === '1') {
            $('#silent_submit').val('0');
          } else {
            location.href = data.location;
          }
        }   
        else {
          $.each(data.messages, function (param,message) {
            var helpblock = $('<p class="validator_message help-block"></p>');
            helpblock.text(message);
            $(myform).find('[name="'+param+'"]').parents('div.controls').first().append(helpblock);
            $(myform).find('[name="'+param+'"]').parents('div.control-group').first().addClass('error');
          });
        }
      },
      error: function() {
        $(myform).find('.alert-error').show();
      } 
    });
    e.preventDefault();
    return false;
  });
};

function setXhrConfirmBtn() {
  var mybtn = this;
  var modal = $('<div class="modal fade">'+
'<form method="post" action="#">'+
'<div class="modal-header"><h3>confirm</h3></div>'+
'<div class="modal-body"><div class="alert alert-error hide">System Error!</div><p>confirm</p></div>'+
'<div class="modal-footer"><input type="submit" class="btn btn-danger" value="confirm" /></div>'+
'</form></div>');
  modal.find('h3').text($(mybtn).text());
  modal.find('input[type=submit]').attr('value',$(mybtn).text());
  modal.find('.modal-body > p').text( $(mybtn).data('confirm') );
  modal.find('form').submit(function(){
    $.ajax({
      type: 'POST',
      url: $(mybtn).data('uri'),
      data: modal.find('form').serialize(),
      success: function(data) {
        modal.find('.alert-error').hide();
        if ( data.error == 0 ) {
          location.href = data.location;
        } 
      },
      error: function() {
        modal.find('.alert-error').show();
      } 
    }); 
    return false;
  });
  $(mybtn).click(function(){
    modal.modal({
      show: true
    });
  });
};
