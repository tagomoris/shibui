CREATE TABLE IF NOT EXISTS queries (
  id             INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  service        VARCHAR(64)   NOT NULL,
  status         SMALLINT      NOT NULL DEFAULT 1,
  query          TEXT          NOT NULL,
  created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  modified_at    TIMESTAMP     NOT NULL DEFAULT '0000-00-00 00:00:00',
  description    VARCHAR(256)  DEFAULT NULL,
  date_field_num SMALLINT      DEFAULT 0,
  date_format    VARCHAR(32)   DEFAULT NULL,
  KEY query_service_search (service,status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS graphs (
  id              INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  query_id        INT           NOT NULL,
  label           VARCHAR(128)  NOT NULL,
  value_field_num SMALLINT      NOT NULL,
  hr_service      VARCHAR(32)   NOT NULL,
  hr_section      VARCHAR(32)   NOT NULL,
  hr_graphname    VARCHAR(32)   NOT NULL,
  KEY graph_query_search (query_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS schedules (
  id              INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  query_id        INT           NOT NULL,
  status          SMALLINT      NOT NULL DEFAULT 1,
  schedule        VARCHAR(128)  NOT NULL, -- crontab like format for DateTime::Event::Cron
  schedule_jp     VARCHAR(128)  NOT NULL,
  created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY schedule_query_search (query_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS histories (
  id              INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  query_id        INT           NOT NULL,
  shib_query_id   VARCHAR(128)  NOT NULL,
  status          VARCHAR(16)   DEFAULT NULL,
  offset          INT           DEFAULT NULL,
  started_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at    TIMESTAMP     NOT NULL DEFAULT '0000-00-00 00:00:00',
  KEY history_query_search (query_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS views (
  id           INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  service      VARCHAR(64)   NOT NULL,
  label        VARCHAR(385)  NOT NULL,
  complex      SMALLINT      NOT NULL DEFAULT 0,
  hr_service   VARCHAR(32)   NOT NULL,
  hr_section   VARCHAR(32)   NOT NULL,
  hr_graphname VARCHAR(32)   NOT NULL,
  created_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY view_service_search (service)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS components (
  id          INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  view_id     INT           NOT NULL,
  query_id    INT NOT NULL,
  KEY component_view_search (view_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS oneshots (
  id            INT           NOT NULL PRIMARY KEY AUTO_INCREMENT,
  query         TEXT          NOT NULL,
  form_items    TEXT          NOT NULL,
  shib_query_id VARCHAR(128)  NOT NULL,
  status        VARCHAR(16)   DEFAULT NULL,
  offset        INT           DEFAULT NULL,
  started_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at  TIMESTAMP     NOT NULL DEFAULT '0000-00-00 00:00:00',
  KEY username_search (created_by(255), id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
