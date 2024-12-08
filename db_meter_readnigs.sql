drop table if exists type_installation;
create table type_installation 
(
	id serial primary key,
	type_name VARCHAR(255) NOT NULL
);
comment on table type_installation is 'Тип размещения приборов учета';
comment on column type_installation.type_name is 'Тип размещения: квартиры многоквартирных домов, частные дома, общедомовые счетчики и тп.';


drop table if exists place_installation;
create table place_installation
(
	id serial primary key,
	id_type_installation int references type_installation (id), 
	city VARCHAR(120) NOT NULL,
	district VARCHAR(60),
	street VARCHAR(120),
	building int,
	entrance VARCHAR(2),
	room int
);
comment on table place_installation is 'Размещение приборов учета';
comment on column place_installation.id_type_installation is 'Идентификатор типа размещения';
comment on column place_installation.city is 'Город размещения';
comment on column place_installation.district is 'Район размещения';
comment on column place_installation.street is 'Улица размещения';
comment on column place_installation.building is 'Номер дома размещения';
comment on column place_installation.entrance is 'Подъезд размещения';
comment on column place_installation.room is 'Номер квартиры размещения';


drop table if exists type_counter;
create table type_counter 
(
	id serial primary key,
	type_name VARCHAR(255) NOT NULL
);
comment on table type_counter is 'Тип прибора учета';
comment on column type_counter.type_name is 'Тип прибора учета: счетчик газа, счетчик электричества, счетчик горячей воды, счетчик холодной воды';


drop table if exists counter;
create table counter
(
	id serial primary key,
	id_type_counter int references type_counter (id), 
	serial_number VARCHAR(120) NOT NULL UNIQUE,
	default_reading INTEGER NOT NULL
);
comment on table counter is 'Прибор учета показаний';
comment on column counter.id_type_counter is 'Идентификатор типа прибора учета';
comment on column counter.serial_number is 'Уникальный серийный номер прибора учета';
comment on column counter.default_reading is 'Дефолтное показание прибора учета';


drop table if exists counter_reading;
create table counter_reading
(
	id serial,
	id_counter int references counter (id) ON DELETE CASCADE, 
	id_place int references place_installation (id) ON DELETE CASCADE, 
	reading_date DATE not null,
	reading_value INTEGER,
	is_success BOOLEAN,
	primary key (id, reading_date)
)
partition by range (reading_date);
comment on table counter_reading is 'Учет показаний приборов';
comment on column counter_reading.id_counter is 'Идентификатор прибора учета';
comment on column counter_reading.id_place is 'Идентификатор места размещения';
comment on column counter_reading.reading_date is 'Дата внесения показания';
comment on column counter_reading.reading_value is 'Вносимое показание';
comment on column counter_reading.is_success is 'Флаг успешности внесения записи';


CREATE OR REPLACE FUNCTION create_partitions(v_date date, v_tablename text, v_columnpart text) 
RETURNS text as
$BODY$
    BEGIN
		/*Функция создания партиций для таблиц*/

		/*
		* пример вызов функции
		* select create_partitions ('2024-01-01'::date, 'counter_reading', 'reading_date');
		*/

      	EXECUTE 'CREATE TABLE IF NOT EXISTS ' || v_tablename || '_' || to_char(v_date, 'YYYY_MM') || 
				' partition of ' || v_tablename || ' for values from ( ' || '''' ||
				date_trunc('month', v_date)::date || '''' || ' ) to ( ' || '''' || 
				date_trunc('month', v_date)::date  + interval '1 month - 1 day' || '''' || ' )';
		
		BEGIN
			EXECUTE 'alter table ' || v_tablename || '_' || to_char(v_date, 'YYYY_MM') || 
					' add constraint partition_check check ( ' || v_columnpart || ' >= ' || 
					'''' || date_trunc('month', v_date)::date || '''' || 
					' and ' || v_columnpart || ' < ' || '''' || 
					date_trunc('month', v_date)::date  + interval '1 month - 1 day' || '''' || ' ) IF NOT EXISTS ';
	   	EXCEPTION WHEN OTHERS 
		THEN
    		RAISE NOTICE 'A constraint partition_check has been created';
			RETURN NULL;
		END;   	
		RETURN NULL;
    END;
$BODY$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION get_counter_reading(v_location VARCHAR, v_end_date DATE)
RETURNS TABLE (
    serial_number VARCHAR,
    type_name VARCHAR,
    default_reading INTEGER,
    address VARCHAR,
    indication_at_begin_period INTEGER,
    indication_at_end_period INTEGER,
    expense_for_period INTEGER
) AS $$
BEGIN
	/*Функция возврата перечня информации приборов учета и их показания*/
	/*
	* пример вызов функции
	* select * from get_counter_reading ('г. Минск, мкр-н. Первомайский, ул. 50 лет Победы, д. 1, корп./под. 1, кв./пом. 1', '2024-12-07');
	*/
    RETURN QUERY
		select 
			c.serial_number, 
			tc.type_name, 
			c.default_reading, 
			trim(case 
				when p.city is not null then 'г. ' || p.city || ', '
				else null
			end || 
			case 
				when p.district is not null then 'мкр-н. ' || p.district || ', '
				else null
			end || 
			case 
				when p.street is not null then 'ул. ' || p.street || ', '
				else null
			end || 
			case 
				when p.building is not null then 'д. ' || p.building || ', '
				else null
			end || 
			case 
				when p.entrance is not null then 'корп./под. ' || p.entrance || ', '
				else null
			end || 
			case 
				when p.room is not null then 'кв./пом. ' || p.room
				else null
			end)::VARCHAR as address,
			min(reading_value) as indication_at_begin_period, 
			max(reading_value) as indication_at_end_period, 
			max(reading_value) - min(reading_value) as expense_for_period
		from public.counter_reading cr
		join public.counter c on
		 	cr.id_counter = c.id
		join public.place_installation p on
		 	cr.id_place = c.id
		join public.type_counter tc on
		 	c.id_type_counter = tc.id
		join public.type_installation ti on
		 	p.id_type_installation = ti.id
		where 
			reading_date >= date_trunc('month', v_end_date)::date
			and reading_date <= v_end_date
		group by 1,2,3,4;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION check_partitions(v_date date, v_tablename text) 
RETURNS table (status int) AS
$BODY$
    BEGIN
		/*Функция проверки партиции для таблицы*/
		/*
		* пример вызов функции
		* select check_partitions('2024-01-01'::date, 'counter_reading');
		*/
		RETURN QUERY EXECUTE 'SELECT case when EXISTS ( SELECT FROM pg_tables WHERE schemaname = ''public'' AND tablename  = ''' ||
					v_tablename || '_' || to_char(v_date, 'YYYY_MM') || ''' ) then 1 else 0 end ';	
    END;
$BODY$
LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION drop_partitions(v_end_date date, v_tablename text) 
RETURNS text AS
$BODY$
	DECLARE
		p_start_date date;
		p_search_date date := '2015-01-01';
		p_status_exists int;
    BEGIN
		/*Функция выгрузки устаревшой информации в формате CSV в определенную папку, открепления партиции и ее удаление*/
		/*
		* пример вызов функции
		* select drop_partitions (current_date, 'counter_reading');
		*/
		p_start_date := v_end_date - interval '3 year';
      	while p_search_date < p_start_date loop
			
			if check_partitions(p_search_date, v_tablename) = 1 then

				EXECUTE 'COPY (select * from ' || v_tablename || '_' || to_char(p_search_date, 'YYYY_MM') || ' ) ' ||
						' TO E''C:\\Program Files\\PostgreSQL\\16\\pgAdmin 4\\' || v_tablename || '_' || to_char(p_search_date, 'YYYY_MM') ||
						'.csv'' with csv header ';
				
				EXECUTE 'ALTER TABLE if exists ' || v_tablename || ' DETACH PARTITION ' || 
						v_tablename || '_' || to_char(p_search_date, 'YYYY_MM') || '  ';
	
				EXECUTE ' DROP TABLE if exists ' || v_tablename || '_' || to_char(p_search_date, 'YYYY_MM');

			end if;
			
			p_search_date := p_search_date + interval '1 month';
			
		end loop;

		RETURN NULL;
	EXCEPTION WHEN OTHERS 
		THEN
    		RAISE NOTICE 'Error: %', SQLERRM;
			RETURN NULL;  	
    END;
$BODY$
LANGUAGE plpgsql;

/* 
 
--примеры вставки данных и вызово функций

INSERT INTO public.type_counter (type_name) VALUES 
('Счетчик газа');

INSERT INTO public.type_installation (type_name) VALUES 
('Квартира многоквартирного дома');

INSERT INTO public.place_installation (id_type_installation,city,district,street,building,entrance,room) VALUES
(1,'Минск','Первомайский','50 лет Победы',1,'1',1);

INSERT INTO public.counter (id_type_counter,serial_number,default_reading) VALUES
(1,'AA12345678AB',1100);

select create_partitions ('2024-01-01'::date, 'counter_reading', 'reading_date');

INSERT INTO public.counter_reading (id_counter,id_place,reading_date,reading_value,is_success) VALUES
(1,1,'2024-12-07',1101,true);

select *
from get_counter_reading ('г. Минск, мкр-н. Первомайский, ул. 50 лет Победы, д. 1, корп./под. 1, кв./пом. 1', '2024-12-07');

select drop_partitions (current_date, 'counter_reading');

*/