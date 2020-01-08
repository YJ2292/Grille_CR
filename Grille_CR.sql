
/* Code création de grille à ne pas toucher descendre plus bas pour mettre paramètre*/
CREATE OR REPLACE FUNCTION generate_hexgrid(width float, xmin float, ymin float, xmax float, ymax float, srid int default 32188)
RETURNS TABLE(
  gid text,
  geom geometry(Polygon)
) AS $grid$
declare
  b float := width / 2;
  a float := tan(radians(30)) * b;  -- tan(30) = 0.577350269
  c float := 2 * a;

  -- NOTE: La longueur d'une maille est (2a + c), ou 1.154700538 * width.

  height float := 2 * (a + c);

  index_xmin int := floor(xmin / width);
  index_ymin int := floor(ymin / height);
  index_xmax int := ceil(xmax / width);
  index_ymax int := ceil(ymax / height);

  snap_xmin float := index_xmin * width;
  snap_ymin float := index_ymin * height;
  snap_xmax float := index_xmax * width;
  snap_ymax float := index_ymax * height;

  ncol int := abs(index_xmax - index_xmin);
  nrow int := abs(index_ymax - index_ymin);

  polygon_string varchar := 'POLYGON((' ||
                                      0 || ' ' || 0         || ' , ' ||
                                      b || ' ' || a         || ' , ' ||
                                      b || ' ' || a + c     || ' , ' ||
                                      0 || ' ' || a + c + a || ' , ' ||
                                 -1 * b || ' ' || a + c     || ' , ' ||
                                 -1 * b || ' ' || a         || ' , ' ||
                                      0 || ' ' || 0         ||
                              '))';
BEGIN
  RETURN QUERY
  SELECT

    format('%s %s %s',
           width,
           x_offset + (1 * x_series + index_xmin),
           y_offset + (2 * y_series + index_ymin)),


    ST_SetSRID(ST_Translate(two_hex.geom,
                            x_series * width + snap_xmin,
                            y_series * height + snap_ymin), srid)

  FROM
    generate_series(0, ncol, 1) AS x_series,
    generate_series(0, nrow, 1) AS y_series,


    (
      
      SELECT
        0 AS x_offset,
        0 AS y_offset,
        polygon_string::geometry AS geom

      UNION
      
      
      SELECT
        0 AS x_offset,
        1 AS y_offset,
        ST_Translate(polygon_string::geometry, b , a + c)  AS geom
    ) AS two_hex;
END;
$grid$ LANGUAGE plpgsql;


/*Choix paramètre pour la création de la table Grille*/
drop table if exists grille; 
Create Table grille as 
 SELECT gid as id_grille, St_AsText(ST_Transform(geom, 32188)) AS geom
    FROM generate_hexgrid(
      -- ENTREZ LA LONGUEUR DE LA DISTANCE INTERNE DES MAILLES 
      220,
      -- ENTREZ LES COORDONNÉES: Coin gauche bas (ST_X) et Coin droit bas (ST_Y)
      ST_X(ST_Transform(ST_SetSRID(ST_GeomFromText('POINT(259889 5021675)'), 32188), 32188)),
      ST_Y(ST_Transform(ST_SetSRID(ST_GeomFromText('POINT(316483 5027841)'), 32188), 32188)),
      -- ENTREZ LES COORDONNÉES: Coin droit haut (ST_X) et coin gauche haut (ST_Y)
      ST_X(ST_Transform(ST_SetSRID(ST_GeomFromText('POINT(316483 5071200)'), 32188), 32188)),
      ST_Y(ST_Transform(ST_SetSRID(ST_GeomFromText('POINT(267323 5070200)'), 32188), 32188)),
      -- ENTREZ LE SYSTÈME DE REFERENCE
      32188
    );

/*Transformer la colonne geom en geometrie */
alter table grille
alter column geom
type geometry(polygon, 32188)
using st_setsrid(st_geomfromtext(geom),32188); 

CREATE INDEX grille_index_spatial ON grille USING GIST (geom);

/*Fin du code pris sur GitHub pour permettre la création d'une grille*/

/*ENTREZ LE NOM DU FICHIER SEGMENT*/
/*Créer la table corridor à l'aide du fichier segement. Le corridor est prolongé*/

drop table if exists segment;
CREATE TABLE segment
(
  id float8,
  poids float8,
  angle float8,
  corridor integer,
  geom text
  );

COPY segment
FROM '/Users/Shared/Projet_Laval/Seg_Laval_200.csv' csv header delimiter ',';  /*Spécifiez la location de votre fichier*/

/* Créer 4 colonnes (xorig_cor, yorig_cor,xdest_cor et ydest_cor) pour pouvoir calculer la nouvelle position des corridors*/

alter table segment
add xorig_cor text;
update segment
set xorig_cor=substring(geom,12,6);


alter table segment
add yorig_cor2 text;
update segment
set yorig_cor2=SUBSTRING(geom,char_length(LEFT(geom,position(' ' in geom)))+1,char_length(geom)-char_length(LEFT(geom,position(' 'in geom)))-char_length(RIGHT(geom,char_length(geom)-position(','in geom)))-1);

alter table segment
add yorig_cor text;
update segment
set yorig_cor=SUBSTRING(yorig_cor2,1,7);

alter table segment
add dest_points text;
update segment
set dest_points=SUBSTRING(geom,char_length(LEFT(geom,position(',' in geom)))+2,char_length(geom)-char_length(LEFT(geom,position(', 'in geom)))-char_length(RIGHT(geom,char_length(geom)-position(')'in geom)))-1);

alter table segment
add xdest_cor text;
update segment
set xdest_cor=SUBSTRING(dest_points,1,6);

alter table segment
add ydest_cor2 text;
update segment
set ydest_cor2=SUBSTRING(dest_points,char_length(LEFT(dest_points,position(' ' in dest_points)))+1,char_length(dest_points)-char_length(LEFT(dest_points,position(' 'in dest_points)))-char_length(RIGHT(geom,char_length(dest_points)-position(')'in dest_points)))-1);


alter table segment
add ydest_cor text;
update segment
set ydest_cor=SUBSTRING(ydest_cor2,1,7);

/* Effacer les colonnes supplémentaires pour calculs intermédiaires qui ont été crées */
alter table segment
drop column dest_points, 
drop column ydest_cor2,
drop column yorig_cor2;

/*Transformation des données text en données geometry (Linestring) et integer (xori_cor,...)*/
ALTER TABLE segment ALTER COLUMN geom TYPE geometry(linestring, 32188) USING st_setsrid(st_geomfromtext(geom),32188);
ALTER TABLE segment ALTER COLUMN xorig_cor  TYPE integer USING (xorig_cor::integer);
ALTER TABLE segment ALTER COLUMN yorig_cor  TYPE integer USING (yorig_cor::integer);
ALTER TABLE segment ALTER COLUMN xdest_cor  TYPE integer USING (xdest_cor::integer);
ALTER TABLE segment ALTER COLUMN ydest_cor  TYPE integer USING (ydest_cor::integer);


/* Calcul de la position pondérée du corridor */
drop table if exists corridor_initial;
Create table corridor_initial as 
select corridor as id, sum(poids) as poids_cor, sum(xorig_cor*poids)/sum(poids) as xorig_cor, 
sum(yorig_cor*poids)/sum(poids) as yorig_cor, sum(xdest_cor*poids)/sum(poids) as xdest_cor,
sum(ydest_cor*poids)/sum(poids) as ydest_cor
from segment 
where corridor<>-1 
group by corridor
order by id;

alter table corridor_initial
add column geom geometry; 
update corridor_initial 
set geom = st_setsrid(st_makeline(st_makepoint(xorig_cor, yorig_cor), st_makepoint(xdest_cor, ydest_cor)), 32188);

/* Tracer le polygone autour des segments*/
drop table if exists polygone_corridor;
Create table polygone_corridor as
SELECT corridor,ST_ConvexHull(ST_Collect(geom)) AS geom
FROM segment
where corridor<>-1 
group by corridor
order by corridor;


/*Prolongement des corridors à un longueur extreme (+5000 mètres) pour faire intersection avec polygone par la suite*/
drop table if exists prolong_corridor;
Create table prolong_corridor as
SELECT id, ST_MakeLine(ST_TRANSLATE(a, sin(az1) * len, cos(az1) * 
len),ST_TRANSLATE(b,sin(az2) * len, cos(az2) * len)) as geom, poids_cor

  FROM (
    SELECT id,poids_cor, a, b, ST_Azimuth(a,b) AS az1, ST_Azimuth(b, a) AS az2, ST_Distance(a,b) + 50000 AS len
      FROM (
        SELECT id,poids_cor, ST_StartPoint(geom) AS b, ST_EndPoint(geom) AS a
          FROM (
select id, /*st_setsrid(st_makeline(st_makepoint(xorig_cor, yorig_cor), st_makepoint(xdest_cor, ydest_cor)), 32188)*/ geom as geom, poids_cor from 
          corridor_initial) a
    ) AS sub
) AS sub2;


/* Effectuer intersection entre polygone convexe et le prolongement extreme des corridors et trouver la bonne mesure des corridors*/
drop table if exists corridor_e;
CREATE TABLE corridor_e AS (
	SELECT prolong_corridor.id,prolong_corridor.poids_cor as cor_weight, ST_AsText(ST_Intersection(prolong_corridor.geom,polygone_corridor.geom)) as geom
	  FROM prolong_corridor,
	       polygone_corridor
	 WHERE prolong_corridor.id = polygone_corridor.corridor
	   AND ST_Intersects(prolong_corridor.geom, polygone_corridor.geom));


/*S'assurer d'avoir les bonnes géométries*/
drop table if exists nbr_seg; 
Create table nbr_seg as
select corridor,count(id) as qte_seg from segment group by corridor order by corridor;


drop table if exists corridor_point;
CREATE TABLE corridor_point as
select nbr_seg.corridor as id, segment.poids,ST_ASText(segment.geom) 
FROM nbr_seg 
LEFT JOIN segment on nbr_seg.corridor=segment.corridor where nbr_seg.qte_seg=1;
 

/* Réinitaliasation de la geométrie des corridors comprenant qu'un seul segment.*/

drop table if exists corridor_ligne;
Create table corridor_ligne AS
Select * 
from corridor_e 
where LEFT(geom,position('(' in geom)-1) ='LINESTRING';

drop table if exists corridor;
CREATE TABLE corridor as
select * from corridor_ligne 
union 
select * from corridor_point;

select count(*) from corridor_point;
/* Créer 4 colonnes (xorig_cor, yorig_cor,xdest_cor et ydest_cor) pour pouvoir par la suite calculer
l'angle du corridor par rapport à l'azimut (Nord 0 degrée) */
alter table corridor
add xorig_cor text;
update corridor
set xorig_cor=substring(geom,12,6);
select * from corridor order by id;

alter table corridor
add yorig_cor2 text;
update corridor
set yorig_cor2=SUBSTRING(geom,char_length(LEFT(geom,position(' ' in geom)))+1,char_length(geom)-char_length(LEFT(geom,position(' 'in geom)))-char_length(RIGHT(geom,char_length(geom)-position(','in geom)))-1);


alter table corridor
add yorig_cor text;
update corridor
set yorig_cor=SUBSTRING(yorig_cor2,1,7);


alter table corridor
add dest_points text;
update corridor
set dest_points=SUBSTRING(geom,char_length(LEFT(geom,position(',' in geom)))+1,char_length(geom)-char_length(LEFT(geom,position(', 'in geom)))-char_length(RIGHT(geom,char_length(geom)-position(')'in geom)))-1);

alter table corridor
add xdest_cor text;
update corridor
set xdest_cor=SUBSTRING(dest_points,1,6);

alter table corridor
add ydest_cor2 text;
update corridor
set ydest_cor2=SUBSTRING(dest_points,char_length(LEFT(dest_points,position(' ' in dest_points)))+1,char_length(dest_points)-char_length(LEFT(dest_points,position(' 'in dest_points)))-char_length(RIGHT(geom,char_length(dest_points)-position(')'in dest_points)))-1);


alter table corridor
add ydest_cor text;
update corridor
set ydest_cor=SUBSTRING(ydest_cor2,1,7);

/* Effacer les colonnes supplémentaires pour calculs intermédiaires qui ont été crées */
alter table corridor
drop column dest_points, 
drop column ydest_cor2,
drop column yorig_cor2;

/*Transformation des données text en données geometry (Linestring) et integer (xori_cor,...)*/
ALTER TABLE corridor ALTER COLUMN geom TYPE geometry(linestring, 32188) USING st_setsrid(st_geomfromtext(geom),32188); 
ALTER TABLE corridor ALTER COLUMN xorig_cor  TYPE integer USING (xorig_cor::integer);
ALTER TABLE corridor ALTER COLUMN yorig_cor  TYPE integer USING (yorig_cor::integer);
ALTER TABLE corridor ALTER COLUMN xdest_cor  TYPE integer USING (xdest_cor::integer);
ALTER TABLE corridor ALTER COLUMN ydest_cor  TYPE integer USING (ydest_cor::integer);

CREATE INDEX corridor_spatial ON corridor USING GIST (geom); /* Creation d'un indez spatial pour accélérer calcul*/

/*Calcul angle du corridor en fonction de l'azimut (Nord 0 degrée)*/
alter table corridor
add angle_cor integer;
update corridor
set angle_cor=degrees(ST_Azimuth(ST_Point(xorig_cor, yorig_cor), ST_Point(xdest_cor,ydest_cor)));

alter table corridor
add longueur_corridor integer;
update corridor
set longueur_corridor=sqrt((xorig_cor-xdest_cor)^2+(yorig_cor-ydest_cor)^2);

select avg(longueur_corridor) from corridor;

select corridor.angle_cor,count(corridor.angle_cor) as nbr from corridor group by corridor.angle_cor order by angle_cor; /*Présente quatité de corridor qui a un certain angle.*/

/*Calcul nombre de corridor par range de angle */
WITH ranges AS (
    SELECT (x*90)::text||'-'||(x*90+89)::text AS range, /*Ecriture de l'équation du range */
           x*90 AS r_min, x*90+89 AS r_max
      FROM generate_series(0,360/90) AS t(x)) /* Jouer avec 90 pour determiner range voulu */
SELECT r.range, count(corridor.*)
  FROM ranges r
 LEFT JOIN corridor ON corridor.angle_cor BETWEEN r.r_min AND r.r_max
 GROUP BY r.range
 ORDER BY count;


/*Pour chacun des scénarios, calcul du nombre angle se trouvant au niveau des limites (+-/10 degrées)
Scénario 1:  0 - 90;   90 - 180; 180 - 270; 270 - 360 
Scénario 2: 30 - 120; 120 - 210; 210 - 300; 300 - 360 + 0 - 30 
Scénario 3: 60 - 150; 150 - 240; 240 - 330; 330 - 360 + 0 - 60 */

drop table if exists limite_scenario1;
Create table limite_scenario1 as
select count(angle_cor) as qte1 from corridor 
where angle_cor between 350 and 360 
OR angle_cor between 0 and 10 
OR angle_cor between 80 and 100 
OR angle_cor between 170 and 190
OR angle_cor between 260 and 280;

select * from limite_scenario1;

drop table if exists limite_scenario2;
Create table limite_scenario2 as
select count(angle_cor) as qte2 from corridor 
where angle_cor between 20 and 40 
OR angle_cor between 110 and 130 
OR angle_cor between 200 and 220 
OR angle_cor between 290 and 310;

select * from limite_scenario2;

drop table if exists limite_scenario3;
Create table limite_scenario3 as
select count(angle_cor) as qte3 from corridor 
where angle_cor between 50 and 70 
OR angle_cor between 140 and 160 
OR angle_cor between 230 and 250 
OR angle_cor between 320 and 340;



select * from limite_scenario3;

/* Creation d'une table resumant les 3 scénarios avant le nombre d'angle se trouvant dans les limites.*/
drop table if exists resume_scenario;
Create table resume_scenario (
id_scenario serial primary key,
scenario_1_qte integer,
scenario_2_qte integer,
scenario_3_qte integer); 

INSERT INTO resume_scenario(scenario_1_qte,scenario_2_qte,scenario_3_qte)
select limite_scenario1.qte1, limite_scenario2.qte2,limite_scenario3.qte3 from limite_scenario1,limite_scenario2,limite_scenario3;

select * from resume_scenario;


/*Recherche intersection corridor et grille - Création grille sans considération angle*/
alter table grille add column poids_cor_total integer;
update grille as a set poids_cor_total = b.compte 
from
(select grille.id_grille, sum(corridor.cor_weight) as compte
  from grille, corridor /* produit scalaire des deux tables, 1ère requête exécutée */
  where st_intersects(grille.geom,corridor.geom) /* où la condition d'intersection est remplie */
  group by grille.id_grille) as b /* Ici, b est la table 'intermédiaire' créer par produit scalaire avec la condition */
  where a.id_grille = b.id_grille;
  update grille set poids_cor_total=0 where poids_cor_total is null;

select * from grille order by poids_cor_total;

/* Creation Table grille vide*/
drop table if exists grille_vide;
Create table grille_vide as 
select grille.id_grille,grille.geom,grille.poids_cor_total from grille where poids_cor_total=0;

/*Creation Table grille Zone1*/
DO $$
DECLARE  
   a integer := 0;  
   b integer := 89;  
   c integer; 
   d integer;
   e integer;
   f integer;
   g integer;
   h integer;
   i integer;
   j integer; 
   k integer;
   l integer;
BEGIN 
IF sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_2_qte) AND sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario  THEN 
	c := a + 0;
	d := b + 0;
	e := a + 90;
	f := b + 90;
	g := a + 180;
	h := b + 180;
	i := a + 270;
	j := b + 270;
	k := 360;
	l := 361;
	RAISE NOTICE'Value of c: %', c;
	RAISE NOTICE'Value of d: %', d;
	RAISE NOTICE'Value of e: %', e;
	RAISE NOTICE'Value of f: %', f;
	RAISE NOTICE'Value of g: %', g;
	RAISE NOTICE'Value of h: %', h;
	RAISE NOTICE'Value of i: %', i;
	RAISE NOTICE'Value of j: %', j;
ELSE 
	IF sum(resume_scenario.scenario_2_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario THEN
		c := a + 30;
		d := b + 30;
		e := c + 90;
		f := d + 90;
		g := c + 180;
		h := d + 180;
		i := c + 270;
		j := d + 270;
		k := 1000;
		l := 1400;
		RAISE NOTICE'Value of c: %', c;
		RAISE NOTICE'Value of d: %', d;
		RAISE NOTICE'Value of e: %', e;
		RAISE NOTICE'Value of f: %', f;
		RAISE NOTICE'Value of g: %', g;
		RAISE NOTICE'Value of h: %', h;
		RAISE NOTICE'Value of i: %', i;
		RAISE NOTICE'Value of j: %', j;
	ELSE
		c := a + 60;
		d := b + 60;
		e := c + 90;
		f := d + 90;
		g := c + 180;
		h := d + 180;
		i := c + 270;
		j := d + 270;
		k := 1500;
		l := 2000;		
		
		RAISE NOTICE'Value of c: %', c;
		RAISE NOTICE'Value of d: %', d;
		RAISE NOTICE'Value of e: %', e;
		RAISE NOTICE'Value of f: %', f;
		RAISE NOTICE'Value of g: %', g;
		RAISE NOTICE'Value of h: %', h;
		RAISE NOTICE'Value of i: %', i;
		RAISE NOTICE'Value of j: %', j;   
	END IF;
END IF;


drop table if exists cor_zone1; /* Creation d'une table ou on garde corridor dans plage angle*/
Create table cor_zone1 as 
select id,cor_weight, geom,angle_cor from corridor where angle_cor between c and d or angle_cor between k and l;
END $$;
CREATE INDEX cor_zone1_index_spatial ON cor_zone1 USING GIST (geom);
select * from cor_zone1;

/* Bon code */

alter table grille add column poids_cor_zone1 integer;
update grille as a set poids_cor_zone1 = b.compte 
from
(select grille.id_grille, sum(cor_zone1.cor_weight) as compte
  from grille, cor_zone1 /* produit scalaire des deux tables, 1ère requête exécutée */
  where st_intersects(grille.geom,cor_zone1.geom) /* où la condition d'intersection est remplie */
  group by grille.id_grille) as b /* Ici, b est la table 'intermédiaire' créer par produit scalaire avec la condition */
  where a.id_grille = b.id_grille;
  update grille set poids_cor_zone1=0 where poids_cor_zone1 is null;

drop table if exists grille_zone1;
Create Table grille_zone1 as /* Creation final de la grille zone1 */
select grille.id_grille,grille.geom,grille.poids_cor_zone1 from grille where poids_cor_zone1>0; /*Creation distribution des angles des corridors*/


/*Creation Table grille zone 2*/
DO $$
DECLARE  
   a integer := 90;  
   b integer := 179;
   e integer;
   f integer;
BEGIN 
IF sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_2_qte) AND sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario  THEN 
	e := a + 0;
	f := b + 0;
	RAISE NOTICE'Value of e: %', e;
	RAISE NOTICE'Value of f: %', f;

ELSE 
	IF sum(resume_scenario.scenario_2_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario THEN
		e := a + 30;
		f := b + 30;
		RAISE NOTICE'Value of e: %', e;
		RAISE NOTICE'Value of f: %', f;
	ELSE
		e := a + 60;
		f := b + 60;	
		RAISE NOTICE'Value of e: %', e;
		RAISE NOTICE'Value of f: %', f;
	END IF;
END IF;

drop table if exists cor_zone2; /* Creation d'une table ou on garde corridor dans plage angle*/
Create table cor_zone2 as 
select id,cor_weight, geom,angle_cor from corridor where angle_cor between e and f;
END$$;
CREATE INDEX cor_zone2_index_spatial ON cor_zone2 USING GIST (geom);

alter table grille add column poids_cor_zone2 integer;
update grille as a set poids_cor_zone2 = b.compte 
from
(select grille.id_grille, sum(cor_zone2.cor_weight) as compte
  from grille, cor_zone2 /* produit scalaire des deux tables, 1ère requête exécutée */
  where st_intersects(grille.geom,cor_zone2.geom) /* où la condition d'intersection est remplie */
  group by grille.id_grille) as b /* Ici, b est la table 'intermédiaire' créer par produit scalaire avec la condition */
  where a.id_grille = b.id_grille;
  update grille set poids_cor_zone2=0 where poids_cor_zone2 is null;
  
drop table if exists grille_zone2;
Create Table grille_zone2 as /* Creation final de la grille zone 2 */
select grille.id_grille,grille.geom,grille.poids_cor_zone2 from grille where poids_cor_zone2>0; 

/*Creation Table grille Zone 3*/
DO $$
DECLARE  
   a integer := 180;  
   b integer := 269;
   g integer;
   h integer;
BEGIN 
IF sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_2_qte) AND sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario  THEN 
	g := a + 0;
	h := b + 0;
	RAISE NOTICE'Value of g: %', g;
	RAISE NOTICE'Value of h: %', h;
ELSE 
	IF sum(resume_scenario.scenario_2_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario THEN
		g := a + 30;
		h := b + 30;
		RAISE NOTICE'Value of g: %', g;
		RAISE NOTICE'Value of h: %', h;
	ELSE
		g := a + 60;
		h := b + 60;	
		RAISE NOTICE'Value of g: %', g;
		RAISE NOTICE'Value of h: %', h;
	END IF;
END IF;
drop table if exists cor_zone3; /* Creation d'une table ou on garde corridor dans plage angle*/
Create table cor_zone3 as 
select id,cor_weight, geom,angle_cor from corridor where angle_cor between g and h;
END$$;
CREATE INDEX cor_zone3_index_spatial ON cor_zone3 USING GIST (geom);

alter table grille add column poids_cor_zone3 integer;
update grille as a set poids_cor_zone3 = b.compte 
from
(select grille.id_grille, sum(cor_zone3.cor_weight) as compte
  from grille, cor_zone3 /* produit scalaire des deux tables, 1ère requête exécutée */
  where st_intersects(grille.geom,cor_zone3.geom) /* où la condition d'intersection est remplie */
  group by grille.id_grille) as b /* Ici, b est la table 'intermédiaire' créer par produit scalaire avec la condition */
  where a.id_grille = b.id_grille;
  update grille set poids_cor_zone3=0 where poids_cor_zone3 is null;

drop table if exists grille_zone3;
Create Table grille_zone3 as /* Creation final de la grille zone 3 */
select grille.id_grille,grille.geom,grille.poids_cor_zone3 from grille where poids_cor_zone3>0;


select * from grille_zone3;
/*Creation Table grille Zone 4*/
DO $$
DECLARE  
   a integer := 270;  
   b integer := 359;
   i integer;
   j integer;
   k integer;
   l integer;
BEGIN 
IF sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_2_qte) AND sum(resume_scenario.scenario_1_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario  THEN 
	i := a + 0;
	j := b + 0;
	k := 1000;
	l := 1001;
	RAISE NOTICE'Value of i: %', i;
	RAISE NOTICE'Value of j: %', j;
ELSE 
	IF sum(resume_scenario.scenario_2_qte) <= sum (resume_scenario.scenario_3_qte) from resume_scenario THEN
		i := a + 30;
		j := b + 30;
		k := 0;
		l := 29;
		RAISE NOTICE'Value of i: %', i;
		RAISE NOTICE'Value of j: %', j;
		RAISE NOTICE'Value of k: %', k;
		RAISE NOTICE'Value of l: %', l;
	ELSE
		i := a + 60;
		j := b + 60;
		k := 0;
		l := 59;	
		RAISE NOTICE'Value of i: %', i;
		RAISE NOTICE'Value of j: %', j;
		RAISE NOTICE'Value of k: %', k;
		RAISE NOTICE'Value of l: %', l;
	END IF;
END IF;
drop table if exists cor_zone4; /* Creation d'une table ou on garde corridor dans plage angle*/
Create table cor_zone4 as 
select id,cor_weight, geom,angle_cor from corridor where angle_cor between i and j or angle_cor between k and l ;
END$$;
CREATE INDEX cor_zone4_index_spatial ON cor_zone4 USING GIST (geom);

alter table grille add column poids_cor_zone4 integer;
update grille as a set poids_cor_zone4 = b.compte 
from
(select grille.id_grille, sum(cor_zone4.cor_weight) as compte
  from grille, cor_zone4 /* produit scalaire des deux tables, 1ère requête exécutée */
  where st_intersects(grille.geom,cor_zone4.geom) /* où la condition d'intersection est remplie */
  group by grille.id_grille) as b /* Ici, b est la table 'intermédiaire' créer par produit scalaire avec la condition */
  where a.id_grille = b.id_grille;
  update grille set poids_cor_zone4=0 where poids_cor_zone4 is null;

drop table if exists grille_zone4;
Create Table grille_zone4 as /* Creation final de la grille zone 4 */
select grille.id_grille,grille.geom,grille.poids_cor_zone4 from grille where poids_cor_zone4>0; 


select * from grille order by poids_cor_total;

select * from cor_zone2;


/*%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%*/
/*S'assurer qu'il n'y a pas un double comptage au niveau des cellules*/

/*Calcul du nombre de corridor dans chaque grille*/
SELECT grille_zone2.id_grille, count (cor_zone2.*)
FROM grille_zone2 
JOIN cor_zone2  ON ST_Intersects(grille_zone2.geom, cor_zone2.geom)
GROUP BY grille_zone2.id_grille; 

/*ZONE 1 */
/*trouver quel corridor est dans quel cellule*/
drop table if exists corridor_cel_zone1;
Create Table corridor_cel_zone1 as
SELECT grille_zone1.id_grille, cor_zone1.id as corridor_id,grille_zone1.geom
FROM grille_zone1 
JOIN cor_zone1  ON ST_Intersects(grille_zone1.geom, cor_zone1.geom)
order by cor_zone1.id;


/*Recherche de quels segments appartiennent à quel cellule*/
drop table if exists segment_cel_zone1;
Create Table segment_cel_zone1 as
select corridor_cel_zone1.id_grille,corridor_cel_zone1.corridor_id,corridor_cel_zone1.geom,segment.id as segment_id,segment.poids as poids_segment 
from segment 
right JOIN corridor_cel_zone1 on segment.corridor=corridor_cel_zone1.corridor_id
order by id_grille, segment_id;

/*Nettoyage de tout doublon (repitition d'un même segment dans une cellule de la grille)*/
drop table  if exists grille_zone1_sansdoublon;
Create Table grille_zone1_sansdoublon as
SELECT id_grille, corridor_id, segment_id, poids_segment,geom,
segment_id- LAG (segment_id,1) OVER (PARTITION BY id_grille ORDER BY segment_id) AS doublon
FROM segment_cel_zone1;

UPDATE grille_zone1_sansdoublon
SET doublon = 1111 /* Choix d'un chiffre différent de 0 */
WHERE
   doublon IS NULL;

/*Creation de la table finale pour la grille de la zone 1*/
drop table if exists grille_zone1_final;
Create Table grille_zone1_final as
select id_grille, geom, ceil(sum(poids_segment)) as poids_cellule 
from grille_zone1_sansdoublon where doublon <>0 group by id_grille,geom order by id_grille;


/*ZONE 2*/
/*trouver quel corridor est dans quel cellule*/
drop table if exists corridor_cel_zone2;
Create Table corridor_cel_zone2 as
SELECT grille_zone2.id_grille, cor_zone2.id as corridor_id,grille_zone2.geom
FROM grille_zone2 
JOIN cor_zone2  ON ST_Intersects(grille_zone2.geom, cor_zone2.geom)
order by cor_zone2.id;

/*Recherche de quels segments appartiennent à quel cellule*/
drop table if exists segment_cel_zone2;
Create Table segment_cel_zone2 as
select corridor_cel_zone2.id_grille,corridor_cel_zone2.corridor_id,corridor_cel_zone2.geom,segment.id as segment_id,segment.poids as poids_segment 
from segment 
right JOIN corridor_cel_zone2 on segment.corridor=corridor_cel_zone2.corridor_id
order by id_grille, segment_id;

/*Nettoyage de tout doublon (repitition d'un même segment dans une cellule de la grille)*/
drop table  if exists grille_zone2_sansdoublon;
Create Table grille_zone2_sansdoublon as
SELECT id_grille, corridor_id, segment_id, poids_segment,geom,
segment_id- LAG (segment_id,1) OVER (PARTITION BY id_grille ORDER BY segment_id) AS doublon
FROM segment_cel_zone2;

UPDATE grille_zone2_sansdoublon
SET doublon = 1111 /* Choix d'un chiffre différent de 0 */
WHERE
   doublon IS NULL;

/*Creation de la table finale pour la grille de la zone 2*/
drop table if exists grille_zone2_final;
Create Table grille_zone2_final as
SELECT id_grille, geom, ceil(sum(poids_segment)) as poids_cellule 
FROM grille_zone2_sansdoublon where doublon <>0 group by id_grille,geom 
ORDER BY id_grille;

/*ZONE 3*/
/*trouver quel corridor est dans quel cellule*/
drop table if exists corridor_cel_zone3;
Create Table corridor_cel_zone3 as
SELECT grille_zone3.id_grille, cor_zone3.id as corridor_id,grille_zone3.geom
FROM grille_zone3 
JOIN cor_zone3  ON ST_Intersects(grille_zone3.geom, cor_zone3.geom)
order by cor_zone3.id;

/*Recherche de quels segments appartiennent à quel cellule*/
drop table if exists segment_cel_zone3;
Create Table segment_cel_zone3 as
select corridor_cel_zone3.id_grille,corridor_cel_zone3.corridor_id,corridor_cel_zone3.geom,segment.id as segment_id,segment.poids as poids_segment 
from segment 
right JOIN corridor_cel_zone3 on segment.corridor=corridor_cel_zone3.corridor_id
order by id_grille, segment_id;

/*Nettoyage de tout doublon (repitition d'un même segment dans une cellule de la grille)*/
drop table  if exists grille_zone3_sansdoublon;
Create Table grille_zone3_sansdoublon as
SELECT id_grille, corridor_id, segment_id, poids_segment,geom,
segment_id- LAG (segment_id,1) OVER (PARTITION BY id_grille ORDER BY segment_id) AS doublon
FROM segment_cel_zone3;

UPDATE grille_zone3_sansdoublon
SET doublon = 1111 /* Choix d'un chiffre différent de 0 */
WHERE
   doublon IS NULL;

/*Creation de la table finale pour la grille de la zone 3*/
drop table if exists grille_zone3_final;
Create Table grille_zone3_final as
select id_grille, geom, ceil(sum(poids_segment)) as poids_cellule 
from grille_zone3_sansdoublon where doublon <>0 group by id_grille,geom 
ORDER BY id_grille;


/*ZONE 4*/
/*trouver quel corridor est dans quel cellule*/
drop table if exists corridor_cel_zone4;
Create Table corridor_cel_zone4 as
SELECT grille_zone4.id_grille, cor_zone4.id as corridor_id,grille_zone4.geom
FROM grille_zone4 
JOIN cor_zone4  ON ST_Intersects(grille_zone4.geom, cor_zone4.geom)
order by cor_zone4.id;


/*Recherche de quels segments appartiennent à quel cellule*/
drop table if exists segment_cel_zone4;
Create Table segment_cel_zone4 as
select corridor_cel_zone4.id_grille,corridor_cel_zone4.corridor_id,corridor_cel_zone4.geom,segment.id as segment_id,segment.poids as poids_segment 
from segment 
right JOIN corridor_cel_zone4 on segment.corridor=corridor_cel_zone4.corridor_id
order by id_grille, segment_id;


/*Nettoyage de tout doublon (repitition d'un même segment dans une cellule de la grille)*/
drop table  if exists grille_zone4_sansdoublon;
Create Table grille_zone4_sansdoublon as
SELECT id_grille, corridor_id, segment_id, poids_segment,geom,
segment_id- LAG (segment_id,1) OVER (PARTITION BY id_grille ORDER BY segment_id)  AS doublon
FROM segment_cel_zone4;

UPDATE grille_zone4_sansdoublon
SET doublon = 1111 /* Choix d'un chiffre différent de 0 */
WHERE
   doublon IS NULL;


/*Creation de la table finale pour la grille de la zone 4*/
drop table if exists grille_zone4_final;
Create Table grille_zone4_final as
select id_grille, geom, ceil(sum(poids_segment)) as poids_cellule 
from grille_zone4_sansdoublon where doublon <> 0 group by id_grille,geom 
order by id_grille;


select id_grille, st_astext(geom), poids_cellule from grille_zone4_final;
