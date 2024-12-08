--
-- PostgreSQL database dump
--

-- Dumped from database version 16.6
-- Dumped by pg_dump version 16.6

-- Started on 2024-12-08 20:31:52

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'WIN1251';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

DROP DATABASE meter_readings;
--
-- TOC entry 4916 (class 1262 OID 16562)
-- Name: meter_readings; Type: DATABASE; Schema: -; Owner: postgres
--

CREATE DATABASE meter_readings WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'Russian_Belarus.1251';


ALTER DATABASE meter_readings OWNER TO postgres;

\connect meter_readings

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'WIN1251';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 233 (class 1255 OID 17255)
-- Name: check_partitions(date, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.check_partitions(v_date date, v_tablename text) RETURNS TABLE(status integer)
    LANGUAGE plpgsql
    AS $$
    BEGIN
		/*Функция проверки партиции для таблицы*/
		/*
		* пример вызов функции
		* select check_partitions('2024-01-01'::date, 'counter_reading');
		*/
		RETURN QUERY EXECUTE 'SELECT case when EXISTS ( SELECT FROM pg_tables WHERE schemaname = ''public'' AND tablename  = ''' ||
					v_tablename || '_' || to_char(v_date, 'YYYY_MM') || ''' ) then 1 else 0 end ';	
    END;
$$;


ALTER FUNCTION public.check_partitions(v_date date, v_tablename text) OWNER TO postgres;

--
-- TOC entry 245 (class 1255 OID 16621)
-- Name: create_partitions(date, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_partitions(v_date date, v_tablename text, v_columnpart text) RETURNS text
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.create_partitions(v_date date, v_tablename text, v_columnpart text) OWNER TO postgres;

--
-- TOC entry 247 (class 1255 OID 17251)
-- Name: drop_partitions(date, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.drop_partitions(v_end_date date, v_tablename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.drop_partitions(v_end_date date, v_tablename text) OWNER TO postgres;

--
-- TOC entry 246 (class 1255 OID 17151)
-- Name: get_counter_reading(character varying, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.get_counter_reading(v_location character varying, v_end_date date) RETURNS TABLE(serial_number character varying, type_name character varying, default_reading integer, address character varying, indication_at_begin_period integer, indication_at_end_period integer, expense_for_period integer)
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.get_counter_reading(v_location character varying, v_end_date date) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 222 (class 1259 OID 16976)
-- Name: counter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter (
    id integer NOT NULL,
    id_type_counter integer,
    serial_number character varying(120) NOT NULL,
    default_reading integer NOT NULL
);


ALTER TABLE public.counter OWNER TO postgres;

--
-- TOC entry 4917 (class 0 OID 0)
-- Dependencies: 222
-- Name: TABLE counter; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.counter IS 'Прибор учета показаний';


--
-- TOC entry 4918 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN counter.id_type_counter; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter.id_type_counter IS 'Идентификатор типа прибора учета';


--
-- TOC entry 4919 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN counter.serial_number; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter.serial_number IS 'Уникальный серийный номер прибора учета';


--
-- TOC entry 4920 (class 0 OID 0)
-- Dependencies: 222
-- Name: COLUMN counter.default_reading; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter.default_reading IS 'Дефолтное показание прибора учета';


--
-- TOC entry 221 (class 1259 OID 16975)
-- Name: counter_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.counter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.counter_id_seq OWNER TO postgres;

--
-- TOC entry 4921 (class 0 OID 0)
-- Dependencies: 221
-- Name: counter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.counter_id_seq OWNED BY public.counter.id;


--
-- TOC entry 224 (class 1259 OID 16990)
-- Name: counter_reading; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading (
    id integer NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
)
PARTITION BY RANGE (reading_date);


ALTER TABLE public.counter_reading OWNER TO postgres;

--
-- TOC entry 4922 (class 0 OID 0)
-- Dependencies: 224
-- Name: TABLE counter_reading; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.counter_reading IS 'Учет показаний приборов';


--
-- TOC entry 4923 (class 0 OID 0)
-- Dependencies: 224
-- Name: COLUMN counter_reading.id_counter; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter_reading.id_counter IS 'Идентификатор прибора учета';


--
-- TOC entry 4924 (class 0 OID 0)
-- Dependencies: 224
-- Name: COLUMN counter_reading.id_place; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter_reading.id_place IS 'Идентификатор места размещения';


--
-- TOC entry 4925 (class 0 OID 0)
-- Dependencies: 224
-- Name: COLUMN counter_reading.reading_date; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter_reading.reading_date IS 'Дата внесения показания';


--
-- TOC entry 4926 (class 0 OID 0)
-- Dependencies: 224
-- Name: COLUMN counter_reading.reading_value; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter_reading.reading_value IS 'Вносимое показание';


--
-- TOC entry 4927 (class 0 OID 0)
-- Dependencies: 224
-- Name: COLUMN counter_reading.is_success; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.counter_reading.is_success IS 'Флаг успешности внесения записи';


--
-- TOC entry 223 (class 1259 OID 16989)
-- Name: counter_reading_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.counter_reading_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.counter_reading_id_seq OWNER TO postgres;

--
-- TOC entry 4928 (class 0 OID 0)
-- Dependencies: 223
-- Name: counter_reading_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.counter_reading_id_seq OWNED BY public.counter_reading.id;


--
-- TOC entry 226 (class 1259 OID 17324)
-- Name: counter_reading_2022_01; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2022_01 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2022_01 OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 17336)
-- Name: counter_reading_2022_02; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2022_02 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2022_02 OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 17384)
-- Name: counter_reading_2022_06; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2022_06 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2022_06 OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 17408)
-- Name: counter_reading_2022_08; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2022_08 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2022_08 OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 17420)
-- Name: counter_reading_2022_09; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2022_09 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2022_09 OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 17372)
-- Name: counter_reading_2023_05; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2023_05 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2023_05 OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 17396)
-- Name: counter_reading_2023_07; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2023_07 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2023_07 OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 17138)
-- Name: counter_reading_2024_12; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.counter_reading_2024_12 (
    id integer DEFAULT nextval('public.counter_reading_id_seq'::regclass) NOT NULL,
    id_counter integer,
    id_place integer,
    reading_date date NOT NULL,
    reading_value integer,
    is_success boolean
);


ALTER TABLE public.counter_reading_2024_12 OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 16957)
-- Name: place_installation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.place_installation (
    id integer NOT NULL,
    id_type_installation integer,
    city character varying(120) NOT NULL,
    district character varying(60),
    street character varying(120),
    building integer,
    entrance character varying(2),
    room integer
);


ALTER TABLE public.place_installation OWNER TO postgres;

--
-- TOC entry 4929 (class 0 OID 0)
-- Dependencies: 218
-- Name: TABLE place_installation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.place_installation IS 'Размещение приборов учета';


--
-- TOC entry 4930 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.id_type_installation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.id_type_installation IS 'Идентификатор типа размещения';


--
-- TOC entry 4931 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.city; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.city IS 'Город размещения';


--
-- TOC entry 4932 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.district; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.district IS 'Район размещения';


--
-- TOC entry 4933 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.street; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.street IS 'Улица размещения';


--
-- TOC entry 4934 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.building; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.building IS 'Номер дома размещения';


--
-- TOC entry 4935 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.entrance; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.entrance IS 'Подъезд размещения';


--
-- TOC entry 4936 (class 0 OID 0)
-- Dependencies: 218
-- Name: COLUMN place_installation.room; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.place_installation.room IS 'Номер квартиры размещения';


--
-- TOC entry 217 (class 1259 OID 16956)
-- Name: place_installation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.place_installation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.place_installation_id_seq OWNER TO postgres;

--
-- TOC entry 4937 (class 0 OID 0)
-- Dependencies: 217
-- Name: place_installation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.place_installation_id_seq OWNED BY public.place_installation.id;


--
-- TOC entry 220 (class 1259 OID 16969)
-- Name: type_counter; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.type_counter (
    id integer NOT NULL,
    type_name character varying(255) NOT NULL
);


ALTER TABLE public.type_counter OWNER TO postgres;

--
-- TOC entry 4938 (class 0 OID 0)
-- Dependencies: 220
-- Name: TABLE type_counter; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.type_counter IS 'Тип прибора учета';


--
-- TOC entry 4939 (class 0 OID 0)
-- Dependencies: 220
-- Name: COLUMN type_counter.type_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.type_counter.type_name IS 'Тип прибора учета: счетчик газа, счетчик электричества, счетчик горячей воды, счетчик холодной воды';


--
-- TOC entry 219 (class 1259 OID 16968)
-- Name: type_counter_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.type_counter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.type_counter_id_seq OWNER TO postgres;

--
-- TOC entry 4940 (class 0 OID 0)
-- Dependencies: 219
-- Name: type_counter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.type_counter_id_seq OWNED BY public.type_counter.id;


--
-- TOC entry 216 (class 1259 OID 16950)
-- Name: type_installation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.type_installation (
    id integer NOT NULL,
    type_name character varying(255) NOT NULL
);


ALTER TABLE public.type_installation OWNER TO postgres;

--
-- TOC entry 4941 (class 0 OID 0)
-- Dependencies: 216
-- Name: TABLE type_installation; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON TABLE public.type_installation IS 'Тип размещения приборов учета';


--
-- TOC entry 4942 (class 0 OID 0)
-- Dependencies: 216
-- Name: COLUMN type_installation.type_name; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.type_installation.type_name IS 'Тип размещения: квартиры многоквартирных домов, частные дома, общедомовые счетчики и тп.';


--
-- TOC entry 215 (class 1259 OID 16949)
-- Name: type_installation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.type_installation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.type_installation_id_seq OWNER TO postgres;

--
-- TOC entry 4943 (class 0 OID 0)
-- Dependencies: 215
-- Name: type_installation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.type_installation_id_seq OWNED BY public.type_installation.id;


--
-- TOC entry 4691 (class 0 OID 0)
-- Name: counter_reading_2022_01; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2022_01 FOR VALUES FROM ('2022-01-01') TO ('2022-01-31');


--
-- TOC entry 4692 (class 0 OID 0)
-- Name: counter_reading_2022_02; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2022_02 FOR VALUES FROM ('2022-02-01') TO ('2022-02-28');


--
-- TOC entry 4694 (class 0 OID 0)
-- Name: counter_reading_2022_06; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2022_06 FOR VALUES FROM ('2022-06-01') TO ('2022-06-30');


--
-- TOC entry 4696 (class 0 OID 0)
-- Name: counter_reading_2022_08; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2022_08 FOR VALUES FROM ('2022-08-01') TO ('2022-08-31');


--
-- TOC entry 4697 (class 0 OID 0)
-- Name: counter_reading_2022_09; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2022_09 FOR VALUES FROM ('2022-09-01') TO ('2022-09-30');


--
-- TOC entry 4693 (class 0 OID 0)
-- Name: counter_reading_2023_05; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2023_05 FOR VALUES FROM ('2023-05-01') TO ('2023-05-31');


--
-- TOC entry 4695 (class 0 OID 0)
-- Name: counter_reading_2023_07; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2023_07 FOR VALUES FROM ('2023-07-01') TO ('2023-07-31');


--
-- TOC entry 4690 (class 0 OID 0)
-- Name: counter_reading_2024_12; Type: TABLE ATTACH; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ATTACH PARTITION public.counter_reading_2024_12 FOR VALUES FROM ('2024-12-01') TO ('2024-12-31');


--
-- TOC entry 4701 (class 2604 OID 16979)
-- Name: counter id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter ALTER COLUMN id SET DEFAULT nextval('public.counter_id_seq'::regclass);


--
-- TOC entry 4702 (class 2604 OID 16993)
-- Name: counter_reading id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading ALTER COLUMN id SET DEFAULT nextval('public.counter_reading_id_seq'::regclass);


--
-- TOC entry 4699 (class 2604 OID 16960)
-- Name: place_installation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.place_installation ALTER COLUMN id SET DEFAULT nextval('public.place_installation_id_seq'::regclass);


--
-- TOC entry 4700 (class 2604 OID 16972)
-- Name: type_counter id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.type_counter ALTER COLUMN id SET DEFAULT nextval('public.type_counter_id_seq'::regclass);


--
-- TOC entry 4698 (class 2604 OID 16953)
-- Name: type_installation id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.type_installation ALTER COLUMN id SET DEFAULT nextval('public.type_installation_id_seq'::regclass);


--
-- TOC entry 4901 (class 0 OID 16976)
-- Dependencies: 222
-- Data for Name: counter; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.counter VALUES (1, 1, 'AA12345678AB', 1100);


--
-- TOC entry 4904 (class 0 OID 17324)
-- Dependencies: 226
-- Data for Name: counter_reading_2022_01; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.counter_reading_2022_01 VALUES (109, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (110, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (111, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (112, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (113, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (114, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (115, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (116, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (117, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (118, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (119, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (120, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (121, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (122, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (123, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (124, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (125, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (126, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (127, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (128, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (129, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (130, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (131, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (132, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (133, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (134, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (135, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (136, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (137, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (138, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (139, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (140, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (141, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (142, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (143, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (144, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (145, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (146, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (147, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (148, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (149, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (150, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (151, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (152, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (153, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (154, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (155, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (156, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (157, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (158, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (159, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (160, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (161, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (162, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (163, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (164, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (165, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (166, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (167, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (168, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (169, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (170, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (171, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (172, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (173, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (174, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (175, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (176, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (177, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (178, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (179, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (180, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (181, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (182, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (183, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (184, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (185, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (186, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (187, 1, 1, '2022-01-07', 1101, true);
INSERT INTO public.counter_reading_2022_01 VALUES (188, 1, 1, '2022-01-07', 1101, true);


--
-- TOC entry 4905 (class 0 OID 17336)
-- Dependencies: 227
-- Data for Name: counter_reading_2022_02; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4907 (class 0 OID 17384)
-- Dependencies: 229
-- Data for Name: counter_reading_2022_06; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.counter_reading_2022_06 VALUES (189, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (190, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (191, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (192, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (193, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (194, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (195, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (196, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (197, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (198, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (199, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (200, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (201, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (202, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (203, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (204, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (205, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (206, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (207, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (208, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (209, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (210, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (211, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (212, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (213, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (214, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (215, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (216, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (217, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (218, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (219, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (220, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (221, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (222, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (223, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (224, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (225, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (226, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (227, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (228, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (229, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (230, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (231, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (232, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (233, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (234, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (235, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (236, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (237, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (238, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (239, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (240, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (241, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (242, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (243, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (244, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (245, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (246, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (247, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (248, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (249, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (250, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (251, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (252, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (253, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (254, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (255, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (256, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (257, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (258, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (259, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (260, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (261, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (262, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (263, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (264, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (265, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (266, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (267, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (268, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (269, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (270, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (271, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (272, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (273, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (274, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (275, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (276, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (277, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (278, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (279, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (280, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (281, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (282, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (283, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (284, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (285, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (286, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (287, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (288, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (289, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (290, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (291, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (292, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (293, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (294, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (295, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (296, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (297, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (298, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (299, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (300, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (301, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (302, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (303, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (304, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (305, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (306, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (307, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (308, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (309, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (310, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (311, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (312, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (313, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (314, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (315, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (316, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (317, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (318, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (319, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (320, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (321, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (322, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (323, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (324, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (325, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (326, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (327, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (328, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (329, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (330, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (331, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (332, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (333, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (334, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (335, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (336, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (337, 1, 1, '2022-06-07', 1101, true);
INSERT INTO public.counter_reading_2022_06 VALUES (338, 1, 1, '2022-06-07', 1101, true);


--
-- TOC entry 4909 (class 0 OID 17408)
-- Dependencies: 231
-- Data for Name: counter_reading_2022_08; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4910 (class 0 OID 17420)
-- Dependencies: 232
-- Data for Name: counter_reading_2022_09; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.counter_reading_2022_09 VALUES (339, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (340, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (341, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (342, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (343, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (344, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (345, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (346, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (347, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (348, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (349, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (350, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (351, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (352, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (353, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (354, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (355, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (356, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (357, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (358, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (359, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (360, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (361, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (362, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (363, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (364, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (365, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (366, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (367, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (368, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (369, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (370, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (371, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (372, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (373, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (374, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (375, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (376, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (377, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (378, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (379, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (380, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (381, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (382, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (383, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (384, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (385, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (386, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (387, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (388, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (389, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (390, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (391, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (392, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (393, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (394, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (395, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (396, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (397, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (398, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (399, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (400, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (401, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (402, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (403, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (404, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (405, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (406, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (407, 1, 1, '2022-09-07', 1101, true);
INSERT INTO public.counter_reading_2022_09 VALUES (408, 1, 1, '2022-09-07', 1101, true);


--
-- TOC entry 4906 (class 0 OID 17372)
-- Dependencies: 228
-- Data for Name: counter_reading_2023_05; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4908 (class 0 OID 17396)
-- Dependencies: 230
-- Data for Name: counter_reading_2023_07; Type: TABLE DATA; Schema: public; Owner: postgres
--



--
-- TOC entry 4903 (class 0 OID 17138)
-- Dependencies: 225
-- Data for Name: counter_reading_2024_12; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.counter_reading_2024_12 VALUES (1, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (2, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (3, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (4, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (5, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (6, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (7, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (8, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (9, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (10, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (11, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (12, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (13, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (81, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (82, 1, 1, '2024-12-07', 1101, true);
INSERT INTO public.counter_reading_2024_12 VALUES (83, 1, 1, '2024-12-07', 1101, true);


--
-- TOC entry 4897 (class 0 OID 16957)
-- Dependencies: 218
-- Data for Name: place_installation; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.place_installation VALUES (1, 1, 'Минск', 'Первомайский', '50 лет Победы', 1, '1', 1);


--
-- TOC entry 4899 (class 0 OID 16969)
-- Dependencies: 220
-- Data for Name: type_counter; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.type_counter VALUES (1, 'Счетчик газа');


--
-- TOC entry 4895 (class 0 OID 16950)
-- Dependencies: 216
-- Data for Name: type_installation; Type: TABLE DATA; Schema: public; Owner: postgres
--

INSERT INTO public.type_installation VALUES (1, 'Квартира многоквартирного дома');


--
-- TOC entry 4944 (class 0 OID 0)
-- Dependencies: 221
-- Name: counter_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.counter_id_seq', 1, true);


--
-- TOC entry 4945 (class 0 OID 0)
-- Dependencies: 223
-- Name: counter_reading_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.counter_reading_id_seq', 538, true);


--
-- TOC entry 4946 (class 0 OID 0)
-- Dependencies: 217
-- Name: place_installation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.place_installation_id_seq', 1, true);


--
-- TOC entry 4947 (class 0 OID 0)
-- Dependencies: 219
-- Name: type_counter_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.type_counter_id_seq', 1, true);


--
-- TOC entry 4948 (class 0 OID 0)
-- Dependencies: 215
-- Name: type_installation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.type_installation_id_seq', 1, true);


--
-- TOC entry 4718 (class 2606 OID 16981)
-- Name: counter counter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter
    ADD CONSTRAINT counter_pkey PRIMARY KEY (id);


--
-- TOC entry 4722 (class 2606 OID 16995)
-- Name: counter_reading counter_reading_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading
    ADD CONSTRAINT counter_reading_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4726 (class 2606 OID 17329)
-- Name: counter_reading_2022_01 counter_reading_2022_01_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2022_01
    ADD CONSTRAINT counter_reading_2022_01_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4728 (class 2606 OID 17341)
-- Name: counter_reading_2022_02 counter_reading_2022_02_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2022_02
    ADD CONSTRAINT counter_reading_2022_02_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4732 (class 2606 OID 17389)
-- Name: counter_reading_2022_06 counter_reading_2022_06_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2022_06
    ADD CONSTRAINT counter_reading_2022_06_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4736 (class 2606 OID 17413)
-- Name: counter_reading_2022_08 counter_reading_2022_08_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2022_08
    ADD CONSTRAINT counter_reading_2022_08_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4738 (class 2606 OID 17425)
-- Name: counter_reading_2022_09 counter_reading_2022_09_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2022_09
    ADD CONSTRAINT counter_reading_2022_09_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4730 (class 2606 OID 17377)
-- Name: counter_reading_2023_05 counter_reading_2023_05_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2023_05
    ADD CONSTRAINT counter_reading_2023_05_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4734 (class 2606 OID 17401)
-- Name: counter_reading_2023_07 counter_reading_2023_07_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2023_07
    ADD CONSTRAINT counter_reading_2023_07_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4724 (class 2606 OID 17143)
-- Name: counter_reading_2024_12 counter_reading_2024_12_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter_reading_2024_12
    ADD CONSTRAINT counter_reading_2024_12_pkey PRIMARY KEY (id, reading_date);


--
-- TOC entry 4720 (class 2606 OID 16983)
-- Name: counter counter_serial_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter
    ADD CONSTRAINT counter_serial_number_key UNIQUE (serial_number);


--
-- TOC entry 4714 (class 2606 OID 16962)
-- Name: place_installation place_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.place_installation
    ADD CONSTRAINT place_installation_pkey PRIMARY KEY (id);


--
-- TOC entry 4716 (class 2606 OID 16974)
-- Name: type_counter type_counter_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.type_counter
    ADD CONSTRAINT type_counter_pkey PRIMARY KEY (id);


--
-- TOC entry 4712 (class 2606 OID 16955)
-- Name: type_installation type_installation_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.type_installation
    ADD CONSTRAINT type_installation_pkey PRIMARY KEY (id);


--
-- TOC entry 4740 (class 0 OID 0)
-- Name: counter_reading_2022_01_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2022_01_pkey;


--
-- TOC entry 4741 (class 0 OID 0)
-- Name: counter_reading_2022_02_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2022_02_pkey;


--
-- TOC entry 4743 (class 0 OID 0)
-- Name: counter_reading_2022_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2022_06_pkey;


--
-- TOC entry 4745 (class 0 OID 0)
-- Name: counter_reading_2022_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2022_08_pkey;


--
-- TOC entry 4746 (class 0 OID 0)
-- Name: counter_reading_2022_09_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2022_09_pkey;


--
-- TOC entry 4742 (class 0 OID 0)
-- Name: counter_reading_2023_05_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2023_05_pkey;


--
-- TOC entry 4744 (class 0 OID 0)
-- Name: counter_reading_2023_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2023_07_pkey;


--
-- TOC entry 4739 (class 0 OID 0)
-- Name: counter_reading_2024_12_pkey; Type: INDEX ATTACH; Schema: public; Owner: postgres
--

ALTER INDEX public.counter_reading_pkey ATTACH PARTITION public.counter_reading_2024_12_pkey;


--
-- TOC entry 4748 (class 2606 OID 16984)
-- Name: counter counter_id_type_counter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.counter
    ADD CONSTRAINT counter_id_type_counter_fkey FOREIGN KEY (id_type_counter) REFERENCES public.type_counter(id);


--
-- TOC entry 4749 (class 2606 OID 16996)
-- Name: counter_reading counter_reading_id_counter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE public.counter_reading
    ADD CONSTRAINT counter_reading_id_counter_fkey FOREIGN KEY (id_counter) REFERENCES public.counter(id) ON DELETE CASCADE;


--
-- TOC entry 4750 (class 2606 OID 17001)
-- Name: counter_reading counter_reading_id_place_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE public.counter_reading
    ADD CONSTRAINT counter_reading_id_place_fkey FOREIGN KEY (id_place) REFERENCES public.place_installation(id) ON DELETE CASCADE;


--
-- TOC entry 4747 (class 2606 OID 16963)
-- Name: place_installation place_installation_id_type_installation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.place_installation
    ADD CONSTRAINT place_installation_id_type_installation_fkey FOREIGN KEY (id_type_installation) REFERENCES public.type_installation(id);


-- Completed on 2024-12-08 20:31:52

--
-- PostgreSQL database dump complete
--

