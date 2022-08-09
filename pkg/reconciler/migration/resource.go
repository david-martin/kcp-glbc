package migration

import (
	"context"
	"strings"

	"github.com/kuadrant/kcp-glbc/pkg/util/metadata"
	"github.com/kuadrant/kcp-glbc/pkg/util/workloadMigration"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func (c *Controller) reconcile(ctx context.Context, resource *metav1.Object) error {
	workloadMigration.Process(resource, c.Queue, c.Logger)
	if resource.DeletionTimestamp != nil && !resource.DeletionTimestamp.IsZero() {
		//in 0.5.0 these are never cleaned up properly
		for _, f := range resource.Finalizers {
			if strings.Contains(f, workloadMigration.SyncerFinalizer) {
				metadata.RemoveFinalizer(resource, f)
			}
		}
	}
	return nil
}
