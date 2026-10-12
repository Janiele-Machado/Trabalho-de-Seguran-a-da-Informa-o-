-- Dados 100% ficticios para demonstracao
CREATE TABLE autores (
  id SERIAL PRIMARY KEY,
  nome TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL
);
CREATE TABLE manuscritos (
  id SERIAL PRIMARY KEY,
  titulo TEXT NOT NULL,
  autor_id INT REFERENCES autores(id),
  status TEXT NOT NULL DEFAULT 'recebido',
  nivel_sigilo TEXT NOT NULL DEFAULT 'confidencial',
  embargo_ate DATE
);
CREATE TABLE contratos (
  id SERIAL PRIMARY KEY,
  manuscrito_id INT REFERENCES manuscritos(id),
  adiantamento_rs NUMERIC(12,2),
  royalties_pct NUMERIC(4,2)
);
INSERT INTO autores (nome, email) VALUES
  ('Helena Cardoso', 'helena@exemplo.com'),
  ('Tiago Ribeiro',  'tiago@exemplo.com');
INSERT INTO manuscritos (titulo, autor_id, status, nivel_sigilo, embargo_ate) VALUES
  ('A Sombra do Cerrado - Livro 3', 1, 'em revisao', 'embargado', '2027-03-15'),
  ('Cartas de Pirenopolis',         2, 'recebido',   'confidencial', NULL);
INSERT INTO contratos (manuscrito_id, adiantamento_rs, royalties_pct) VALUES
  (1, 150000.00, 12.00),
  (2,  20000.00, 10.00);
