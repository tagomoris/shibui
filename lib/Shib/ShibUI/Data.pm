package Shib::ShibUI::Data;

use 5.014;
use utf8;
use Log::Minimal;

use Time::Piece;
use Time::Piece::MySQL;
use DBIx::Sunny;
use Scope::Container::DBI;

use Shib::ShibUI;

sub new {
    my $class = shift;
    bless {}, $class;
}

sub dbh {
    my $self = shift;
    local $Scope::Container::DBI::DBI_CLASS = 'DBIx::Sunny';
    Scope::Container::DBI->connect(
        Shib::ShibUI->config->{dsn},
        Shib::ShibUI->config->{db_username},
        Shib::ShibUI->config->{db_password}
    );
}

sub service_list {
    my ($self) = @_;
    my $r = $self->dbh->select_all('SELECT DISTINCT service FROM queries WHERE status=1 ORDER BY service');
    [map {$_->{service}} @$r];
}

sub register_query {
    my ($self, $service, $query) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'INSERT INTO queries (service,query,created_at,modified_at) VALUES (?,?,NOW(),NOW())',
        $service, $query,
    );
    $self->dbh->last_insert_id;
}

sub query {
    my ($self, $query_id) = @_;
    my $query = <<"EOQ";
SELECT id,service,status,query,created_at,modified_at,description,date_field_num,date_format
FROM queries WHERE id=?
EOQ
    $self->dbh->select_row($query, $query_id);
}

sub update_query {
    my ($self, $query_id, $query, $status, $description, $date_field_num, $date_format) = @_;
    my $sql = <<"EOQ";
UPDATE queries SET status=?, query=?, description=?, date_field_num=?, date_format=?, modified_at=NOW()
WHERE id=?
EOQ
    $self->dbh->query($sql, $status, $query, $description, $date_field_num, $date_format, $query_id);
    1;
}

sub queries {
    my ($self, $service) = @_;
    my $query = <<"EOQ";
SELECT id,service,status,query,created_at,modified_at,description,date_field_num,date_format
FROM queries WHERE service=? ORDER BY status DESC, id DESC
EOQ
    $self->dbh->select_all($query, $service);
}

sub query_list {
    my ($self, $query_id_list) = @_;
    my $query = <<"EOQ";
SELECT id,service,status,query,created_at,modified_at,description,date_field_num,date_format
FROM queries WHERE id IN (?)
EOQ
    $self->dbh->select_all($query, $query_id_list);
}

sub delete_query {
    my ($self, $query_id) = @_;
    $self->dbh->query('DELETE FROM queries WHERE id=?', $query_id);
    1;
}

sub graph {
    my ($self, $graph_id) = @_;
    $self->dbh->select_row(
        'SELECT id,query_id,label,value_field_num,hr_service,hr_section,hr_graphname FROM graphs WHERE id=?',
        $graph_id
    );
}

sub search_graphs {
    my ($self, $hr_service, $hr_section, $hr_graphname) = @_;
    my $query = <<EOQ;
SELECT id,query_id,label,value_field_num,hr_service,hr_section,hr_graphname
FROM graphs WHERE hr_service=? AND hr_section=? AND hr_graphname=?
EOQ
    $self->dbh->select_all(
        $query,
        $hr_service, $hr_section, $hr_graphname,
    );
}

sub graphs {
    my ($self, $query_id) = @_;
    $self->dbh->select_all(
        'SELECT id,query_id,label,value_field_num,hr_service,hr_section,hr_graphname FROM graphs WHERE query_id=? ORDER BY id',
        $query_id
    );
}

sub add_graph {
    my ($self, $query_id, $label, $value_field_num, $hr_service, $hr_section, $hr_graphname) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'INSERT INTO graphs (query_id,label,value_field_num,hr_service,hr_section,hr_graphname) VALUES (?,?,?,?,?,?)',
        $query_id, $label, $value_field_num, $hr_service, $hr_section, $hr_graphname
    );
    $dbh->last_insert_id;
}

sub delete_graph {
    my ($self, $graph_id) = @_;
    $self->dbh->query('DELETE FROM graphs WHERE id=?', $graph_id);
    1;
}

sub schedule {
    my ($self, $schedule_id) = @_;
    $self->dbh->select_row(
        'SELECT id,query_id,status,schedule,schedule_jp,created_at FROM schedules WHERE id=?',
        $schedule_id
    );
}

sub schedules {
    my ($self, $query_id) = @_;
    $self->dbh->select_all(
        'SELECT id,query_id,status,schedule,schedule_jp,created_at FROM schedules WHERE query_id=? ORDER BY id',
        $query_id
    );
}

sub valid_schedules {
    my ($self) = @_;
    $self->dbh->select_all(
        'SELECT id,query_id,status,schedule,schedule_jp,created_at FROM schedules WHERE status=1 ORDER BY id'
    );
}

sub add_schedule {
    my ($self, $query_id, $schedule, $schedule_jp) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'INSERT INTO schedules (query_id,status,schedule,schedule_jp) VALUES (?,0,?,?)',
        $query_id, $schedule, $schedule_jp
    );
    $dbh->last_insert_id;
}

sub update_schedule_status {
    my ($self, $schedule_id, $status) = @_;
    $self->dbh->query(
        'UPDATE schedules SET status=? WHERE id=?',
        $status, $schedule_id
    );
    1;
}

sub delete_schedule {
    my ($self, $schedule_id) = @_;
    $self->dbh->query('DELETE FROM schedules WHERE id=?', $schedule_id);
    1;
}

sub history {
    my ($self, $history_id) = @_;
    $self->dbh->select_row(
        'SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at FROM histories WHERE id=?',
        $history_id
    );
}

sub histories {
    my ($self, $query_id) = @_;
    $self->dbh->select_all(
        'SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at FROM histories WHERE query_id=? ORDER BY id',
        $query_id
    );
}

sub history_list {
    my ($self, $query_id_list) = @_;
    my $sql = <<EOQ;
SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at
FROM (
  SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at
  FROM histories
  WHERE status='done' AND query_id in (?)
  ORDER BY id DESC
) tmp
GROUP BY query_id
EOQ
    my $results = $self->dbh->select_all($sql, $query_id_list);
    foreach my $r (@$results) {
        next unless $r->{completed_at} and $r->{started_at};
        my $elapse = Time::Piece->from_mysql_timestamp($r->{completed_at}) - Time::Piece->from_mysql_timestamp($r->{started_at});
        my $elapse_min = int($elapse / 60);
        if ($elapse > 60) {
            $r->{elapse} = int($elapse_min / 60) . 'h' . ($elapse_min % 60) . 'm';
        }
        else {
            $r->{elapse} = $elapse_min . 'm';
        }
    }
    $results;
}

sub history_shib_id {
    my ($self, $query_id, $shib_query_id) = @_;
    $self->dbh->select_row(
        'SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at FROM histories WHERE query_id=? AND shib_query_id=? ORDER BY id DESC LIMIT 1',
        $query_id, $shib_query_id
    );
}

sub last_history {
    my ($self, $query_id) = @_;
    $self->dbh->select_row(
        'SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at FROM histories WHERE query_id=? ORDER BY id DESC LIMIT 1',
        $query_id
    );
}

sub recent_histories {
    my ($self, $query_id, $limit) = @_;
    $limit = 10 unless $limit;
    unless ($limit =~ /^\d+$/) {
        $limit = 10;
    }
    my $sql = 'SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at FROM histories WHERE query_id=? ORDER BY id DESC';
    $sql .= " LIMIT $limit";
    $self->dbh->select_all($sql, $query_id);
}

# histories started but not completed
sub waiting_histories {
    my ($self) = @_;
    $self->dbh->select_all(
        'SELECT id,query_id,shib_query_id,status,offset,started_at,completed_at FROM histories WHERE status=? ORDER BY id',
        'waiting'
    );
}

# none => started
# offset: '-1' => scheduled, 0 or more => specified
sub insert_history {
    my ($self, $query_id, $shib_query_id, $offset) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'INSERT INTO histories (query_id,shib_query_id,status,offset,started_at) VALUES (?,?,?,?,NOW())',
        $query_id, $shib_query_id, 'waiting', $offset
    );
    $dbh->last_insert_id;
}

# started => completed
sub update_history {
    my ($self, $history_id, $status, $completed_at) = @_;
    $self->dbh->query(
        'UPDATE histories SET status=?,completed_at=? WHERE id=?',
        $status, $completed_at, $history_id
    );
    1;
}

sub views {
    my ($self, $service) = @_;
    my $query = <<EOQ;
SELECT id,service,label,complex,hr_service,hr_section,hr_graphname,created_at
        FROM views WHERE service=? ORDER BY complex DESC, id DESC
EOQ
    $self->dbh->select_all($query, $service);
}

sub view {
    my ($self, $view_id) = @_;
    $self->dbh->select_row(
        'SELECT id,service,label,complex,hr_service,hr_section,hr_graphname,created_at FROM views WHERE id=?',
        $view_id
    );
}

sub search_view {
    my ($self, $complex, $hr_service, $hr_section, $hr_graphname) = @_;
    my $query = <<EOQ;
SELECT id,service,label,complex,hr_service,hr_section,hr_graphname,created_at
FROM views WHERE complex=? AND hr_service=? AND hr_section=? AND hr_graphname=?
EOQ
    $self->dbh->select_row($query, $complex, $hr_service, $hr_section, $hr_graphname);
}

sub add_view {
    my ($self, $service, $label, $complex, $hr_service, $hr_section, $hr_graphname) = @_;
    my $dbh = $self->dbh;
    $dbh->query(
        'INSERT INTO views (service,label,complex,hr_service,hr_section,hr_graphname) VALUES (?,?,?,?,?,?)',
        $service, $label, $complex, $hr_service, $hr_section, $hr_graphname
    );
    $dbh->last_insert_id;
}

sub delete_view {
    my ($self, $view_id) = @_;
    $self->dbh->query('DELETE FROM views WHERE id=?', $view_id);
    1;
}

sub components {
    my ($self, $view_id) = @_;
    $self->dbh->select_all('SELECT id,view_id,query_id FROM components WHERE view_id=?', $view_id);
}

sub component {
    my ($self, $component_id) = @_;
    $self->dbh->select_all('SELECT id,view_id,query_id FROM components WHERE id=?', $component_id);
}

sub check_component {
    my ($self, $view_id, $query_id) = @_;
    my $result = $self->dbh->select_row(
        'SELECT count(*) AS cnt FROM components WHERE view_id=? AND query_id=?',
        $view_id, $query_id,
    );
    return $result->{cnt} > 0;
}

sub add_component {
    my ($self, $view_id, $query_id) = @_;
    my $dbh = $self->dbh;
    $dbh->query('INSERT INTO components (view_id,query_id) VALUES (?,?)', $view_id, $query_id);
    $dbh->last_insert_id;
}

sub delete_componnet {
    my ($self, $view_id) = @_;
    $self->dbh->query('DELETE FROM components WHERE view_id=?', $view_id);
    1;
}

sub recent_oneshots {
    my ($self) = @_;
    my $sql = <<EOSQL;
SELECT
 id,query,form_items,shib_query_id,status,started_at,completed_at
FROM oneshots
ORDER BY id DESC LIMIT 20
EOSQL
    $self->dbh->select_all($sql);
}

sub waiting_oneshots {
    my ($self) = @_;
    $self->dbh->select_all(
        'SELECT id,query,form_items,shib_query_id,status,started_at,completed_at FROM oneshots WHERE status=?',
        'waiting'
    );
}

sub oneshot {
    my ($self, $oneshot_id) = @_;
    my $sql = <<EOSQL;
SELECT
 id,query,form_items,shib_query_id,status,started_at,completed_at
FROM oneshots WHERE id=?
EOSQL
    $self->dbh->select_row($sql, $oneshot_id);
}

sub add_oneshot {
    my ($self, $query, $form_items, $shib_query_id, $offset) = @_;
    my $sql = <<EOSQL;
INSERT INTO oneshots (query,form_items,shib_query_id,status,offset) VALUES (?,?,?,?,?)
EOSQL
    my $dbh = $self->dbh;
    $dbh->query($sql, $query, $form_items, $shib_query_id, 'waiting', $offset);
    $dbh->last_insert_id;
}

sub update_oneshot {
    my ($self, $oneshot_id, $status, $completed_at) = @_;
    $self->dbh->query(
        'UPDATE oneshots SET status=?,completed_at=? WHERE id=?',
        $status, $completed_at, $oneshot_id
    );
    1;
}

1;
