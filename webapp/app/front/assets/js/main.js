var userCount = 0;

function addUserSuccess(user) {
    $(`<tr>
            <th scope=\"row\">${userCount + 1}</th>
            <td>${user.username}</td>
            </tr>`).appendTo( "tbody" );

    userCount = userCount + 1;
}

function getUsersSuccess(users) {
    users = users.sort(function(user1, user2) {
        if(user1.username < user2.username) return -1;
        if(user1.username > user2.username) return 1;
        return 0;
    });

    $.each(users, function(index, user) {
        $(`<tr> 
            <th scope=\"row\">${index + 1}</th>
            <td>${user.username}</td>
            </tr>`).appendTo( "tbody" );
    });

    userCount = users.length;
}

function addUser() {
    var data = {
        username: $('#username').val()
    };
    $.ajax({
        method: "POST",
        url: "user",
        data: data,
        success: function() {addUserSuccess(data)},
        dataType: 'json'
    });
}

function getUsers() {
    $.ajax({
        method: "GET",
        url: "users",
        success: function(data) {getUsersSuccess(data)},
        dataType: 'json'
    });
}
