package postgres

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"

	"github.com/mcagricaliskan/scrollary/backend/internal/domain"
)

type folders Store

const folderColumns = `id, library_id, parent_id, kind, name, sort_key, revision, updated_at`

func scanFolder(row pgx.Row) (*domain.Folder, error) {
	var f domain.Folder
	var kind string
	var rev int64
	if err := row.Scan(&f.ID, &f.LibraryID, &f.ParentID, &kind, &f.Name, &f.SortKey, &rev, &f.UpdatedAt); err != nil {
		return nil, err
	}
	f.Kind = domain.FolderKind(kind)
	f.Revision = domain.Revision(rev)
	return &f, nil
}

func (f *folders) Root(ctx context.Context, lib domain.LibraryID) (*domain.Folder, error) {
	fd, err := scanFolder((*Store)(f).pool.QueryRow(ctx,
		`SELECT `+folderColumns+` FROM folders WHERE library_id = $1 AND kind = 'root'`, lib))
	if err != nil {
		return nil, translate(err)
	}
	return fd, nil
}

func (f *folders) Get(ctx context.Context, lib domain.LibraryID, id domain.ID) (*domain.Folder, error) {
	fd, err := scanFolder((*Store)(f).pool.QueryRow(ctx,
		`SELECT `+folderColumns+` FROM folders WHERE library_id = $1 AND id = $2`, lib, id))
	if err != nil {
		return nil, translate(err)
	}
	return fd, nil
}

func (f *folders) Children(ctx context.Context, lib domain.LibraryID, parent domain.ID) ([]*domain.Folder, error) {
	rows, err := (*Store)(f).pool.Query(ctx,
		`SELECT `+folderColumns+` FROM folders
		 WHERE library_id = $1 AND parent_id = $2
		 ORDER BY sort_key, id`, lib, parent)
	if err != nil {
		return nil, translate(err)
	}
	defer rows.Close()
	var out []*domain.Folder
	for rows.Next() {
		fd, err := scanFolder(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, fd)
	}
	return out, rows.Err()
}

func (f *folders) Create(ctx context.Context, fd *domain.Folder) error {
	if err := fd.Validate(); err != nil {
		return err
	}
	_, err := (*Store)(f).pool.Exec(ctx, `
		INSERT INTO folders (id, library_id, parent_id, kind, name, sort_key, revision, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, now())`,
		fd.ID, fd.LibraryID, fd.ParentID, string(fd.Kind), fd.Name, fd.SortKey, int64(fd.Revision))
	return translate(err)
}

func (f *folders) Rename(ctx context.Context, lib domain.LibraryID, id domain.ID, name string) error {
	tag, err := (*Store)(f).pool.Exec(ctx,
		`UPDATE folders SET name = $3, updated_at = now() WHERE library_id = $1 AND id = $2`,
		lib, id, name)
	if err != nil {
		return translate(err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

// Move reparents a folder, refusing a move that would make it its own
// ancestor. The whole check-and-write runs in one transaction holding the
// library row lock, so two concurrent moves cannot commit a cycle together.
func (f *folders) Move(ctx context.Context, lib domain.LibraryID, id, newParent domain.ID) error {
	s := (*Store)(f)
	return s.inTx(ctx, func(tx pgx.Tx) error {
		if err := lockLibrary(ctx, tx, lib); err != nil {
			return err
		}
		fd, err := scanFolder(tx.QueryRow(ctx,
			`SELECT `+folderColumns+` FROM folders WHERE library_id = $1 AND id = $2`, lib, id))
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		if err != nil {
			return err
		}
		if fd.IsRoot() {
			return domain.ErrRootMustNotHaveParent
		}
		var exists bool
		if err := tx.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM folders WHERE library_id = $1 AND id = $2)`,
			lib, newParent).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			return domain.ErrNotFound
		}
		// I2: walk up from the proposed parent; meeting this folder is a cycle.
		var cycle bool
		if err := tx.QueryRow(ctx, `
			WITH RECURSIVE up AS (
				SELECT id, parent_id FROM folders WHERE library_id = $1 AND id = $2
				UNION ALL
				SELECT f.id, f.parent_id FROM folders f JOIN up ON f.id = up.parent_id
			)
			SELECT EXISTS (SELECT 1 FROM up WHERE id = $3)`,
			lib, newParent, id).Scan(&cycle); err != nil {
			return err
		}
		if cycle {
			return domain.ErrFolderCycle
		}
		_, err = tx.Exec(ctx,
			`UPDATE folders SET parent_id = $3, updated_at = now() WHERE library_id = $1 AND id = $2`,
			lib, id, newParent)
		return err
	})
}

// Delete reparents this folder's children to its parent and removes it.
//
// It never touches the content of Collections or Entries: tidying organisation
// must not be a way to destroy content (I5). Returns how many children moved.
func (f *folders) Delete(ctx context.Context, lib domain.LibraryID, id domain.ID) (int, error) {
	s := (*Store)(f)
	moved := 0
	err := s.inTx(ctx, func(tx pgx.Tx) error {
		if err := lockLibrary(ctx, tx, lib); err != nil {
			return err
		}
		fd, err := scanFolder(tx.QueryRow(ctx,
			`SELECT `+folderColumns+` FROM folders WHERE library_id = $1 AND id = $2`, lib, id))
		if errors.Is(err, pgx.ErrNoRows) {
			return domain.ErrNotFound
		}
		if err != nil {
			return err
		}
		if fd.IsRoot() {
			return domain.ErrRootMustNotHaveParent
		}
		parent := *fd.ParentID

		tag, err := tx.Exec(ctx,
			`UPDATE folders SET parent_id = $3, updated_at = now() WHERE library_id = $1 AND parent_id = $2`,
			lib, id, parent)
		if err != nil {
			return err
		}
		moved += int(tag.RowsAffected())

		tag, err = tx.Exec(ctx,
			`UPDATE collections SET folder_id = $3, updated_at = now() WHERE library_id = $1 AND folder_id = $2`,
			lib, id, parent)
		if err != nil {
			return err
		}
		moved += int(tag.RowsAffected())

		tag, err = tx.Exec(ctx,
			`UPDATE entries SET folder_id = $3, updated_at = now() WHERE library_id = $1 AND folder_id = $2`,
			lib, id, parent)
		if err != nil {
			return err
		}
		moved += int(tag.RowsAffected())

		_, err = tx.Exec(ctx,
			`DELETE FROM folders WHERE library_id = $1 AND id = $2`, lib, id)
		return err
	})
	if err != nil {
		return 0, err
	}
	return moved, nil
}
